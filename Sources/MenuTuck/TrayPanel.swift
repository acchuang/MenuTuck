import AppKit
import SwiftUI

/// Pure grid logic for the Tray, kept apart so it can be tested.
enum TrayGrid {
    /// One row up to 6 tiles, then the fewest rows of at most 6, balanced so the last row isn't a stub.
    static func columns(for count: Int) -> Int {
        guard count > 6 else { return max(count, 1) }
        let rows = (count + 5) / 6
        return (count + rows - 1) / rows
    }

    /// Dock badge as shown on a tile: big counts collapse to "99+", text badges stay short.
    static func badgeText(_ raw: String) -> String {
        if let n = Int(raw) { return n > 99 ? "99+" : raw }
        return String(raw.prefix(3))
    }

    /// Pinned first, then running before not running; within each, most opened first,
    /// then Hidden before Always Hidden, in bar order.
    static func tiles(from items: [MenuBarItem], query: String, openCounts: [String: Int] = [:],
                      pinned: Set<String> = []) -> [MenuBarItem] {
        func rank(_ entry: (offset: Int, element: MenuBarItem)) -> (Int, Int, Int, Int, Int) {
            let item = entry.element
            return (pinned.contains(item.storageKey) ? 0 : 1, item.isRunning ? 0 : 1,
                    -(openCounts[item.storageKey] ?? 0), item.section == .hidden ? 0 : 1, entry.offset)
        }
        return items.enumerated()
            .filter { $0.element.section != .visible && $0.element.matches(query) }
            .sorted { rank($0) < rank($1) }
            .map(\.element)
    }

    /// Arrow-key move in a grid of `count` tiles. Stays put at an edge.
    static func move(_ index: Int, keyCode: UInt16, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let current = min(max(index, 0), count - 1)
        let target: Int
        let columns = columns(for: count)
        switch keyCode {
        case 123: target = current - 1
        case 124: target = current + 1
        case 125: target = current + columns
        case 126: target = current - columns
        default: return current
        }
        return (0..<count).contains(target) ? target : current
    }

    /// True when `chars` is printable text suitable for the Tray filter (rejects control and PUA function keys).
    static func isPrintableFilterInput(_ chars: String) -> Bool {
        !chars.isEmpty && chars.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value)
        }
    }
}

final class TrayState: ObservableObject {
    @Published var query = ""
    @Published var selection = 0
    /// Dock badge text ("3", "!") by bundle ID.
    @Published var badges: [String: String] = [:]
}

enum DockBadges {
    /// Reads each Dock item's badge through Accessibility. Empty if the Dock isn't reachable.
    static func read() -> [String: String] {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [:] }
        func children(_ element: AXUIElement) -> [AXUIElement] {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
            return value as? [AXUIElement] ?? []
        }
        let axDock = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(axDock, 0.25)
        var result: [String: String] = [:]
        for list in children(axDock) {
            for item in children(list) {
                var label: CFTypeRef?
                var url: CFTypeRef?
                AXUIElementCopyAttributeValue(item, "AXStatusLabel" as CFString, &label)
                AXUIElementCopyAttributeValue(item, kAXURLAttribute as CFString, &url)
                guard let text = label as? String, !text.isEmpty,
                      let url = url as? URL, let id = Bundle(url: url)?.bundleIdentifier else { continue }
                result[id] = text
            }
        }
        return result
    }
}

private final class TrayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// A panel under the toggle that lists hidden icons as tiles, so revealing them never
/// pushes anything behind the notch. Keyboard: type to filter, arrows + Enter, 1–9, Esc.
final class TrayController: NSObject, NSWindowDelegate {
    private let model: ItemsModel
    private let state = TrayState()
    private var panel: TrayPanel?
    private var keyMonitor: Any?
    private var outsideClickMonitor: Any?
    private var anchor: CGRect?
    /// A click on the toggle resigns the panel before the click lands; without this it would reopen at once.
    private var closedAt: Date = .distantPast
    var onOpenSettings: (() -> Void)?

    var isOpen: Bool { panel != nil }

    init(model: ItemsModel) {
        self.model = model
    }

    /// `anchor` is the toggle's frame in global CG coordinates (top-left origin).
    func toggle(below anchor: CGRect?) {
        if panel != nil {
            close()
        } else if Date().timeIntervalSince(closedAt) > 0.3 {
            open(below: anchor)
        }
    }

    func show(below anchor: CGRect?) {
        if panel == nil { open(below: anchor) }
    }

    private func open(below anchor: CGRect?) {
        self.anchor = anchor
        state.query = ""
        state.selection = 0
        // Tucked owners only; launch/quit observers already run full scans for new apps.
        let tucked = Set(model.items.filter { $0.section != .visible && $0.isRunning }.map(\.pid))
        model.refresh(onlyPIDs: tucked.isEmpty ? nil : tucked)
        DispatchQueue.global(qos: .userInitiated).async { [state] in
            let badges = DockBadges.read()
            DispatchQueue.main.async { state.badges = badges }
        }

        let view = TrayView(model: model, prefs: .shared, state: state,
                            open: { [weak self] in self?.openItem($0) },
                            openSettings: { [weak self] in self?.openSettings() },
                            closeTray: { [weak self] in self?.close() })
        let panel = TrayPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: view)
        host.sizingOptions = [.preferredContentSize]
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.setContentSize(host.fittingSize)
        self.panel = panel
        reposition()
        panel.makeKeyAndOrderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handleKey(event) ? nil : event
        }
        // A nonactivating panel in an inactive app may never resign key, so watch clicks in other apps too.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    func close() {
        guard panel != nil else { return }
        for monitor in [keyMonitor, outsideClickMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
        keyMonitor = nil
        outsideClickMonitor = nil
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        closedAt = Date()
    }

    func windowDidResignKey(_ notification: Notification) { close() }
    func windowDidResize(_ notification: Notification) { reposition() }

    /// Centered under the toggle, clamped to its screen.
    private func reposition() {
        guard let panel else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let mouse = NSEvent.mouseLocation
        let anchorPoint = anchor.map { CGPoint(x: $0.midX, y: primaryHeight - $0.maxY) } ?? mouse
        let screen = NSScreen.screens.first { $0.frame.insetBy(dx: 0, dy: -1).contains(anchorPoint) } ?? NSScreen.main
        guard let frame = screen?.frame else { return }
        let size = panel.frame.size
        let top = anchor == nil ? (screen?.visibleFrame.maxY ?? frame.maxY) - 6 : anchorPoint.y - 6
        let x = min(max(anchorPoint.x - size.width / 2, frame.minX + 8), frame.maxX - size.width - 8)
        panel.setFrameTopLeftPoint(CGPoint(x: x, y: top))
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let prefs = Preferences.shared
        let tiles = TrayGrid.tiles(from: model.trayCandidates, query: state.query,
                                   openCounts: prefs.openCounts, pinned: prefs.pinned)
        if tiles.isEmpty {
            state.selection = 0
        } else {
            state.selection = min(max(state.selection, 0), tiles.count - 1)
        }
        let command = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 53: // Esc clears a filter first, then closes.
            if state.query.isEmpty { close() } else { state.query = ""; state.selection = 0 }
        case 36, 76: // Return, keypad Enter
            if tiles.indices.contains(state.selection) { openItem(tiles[state.selection]) }
        case 51: // Delete; ⌘Delete clears
            guard !state.query.isEmpty else { return true }
            if command { state.query = "" } else { state.query.removeLast() }
            state.selection = 0
        case 43 where command: // ⌘,
            openSettings()
        case 123...126:
            state.selection = TrayGrid.move(state.selection, keyCode: event.keyCode, count: tiles.count)
        default:
            guard event.modifierFlags.isDisjoint(with: [.command, .control]),
                  let chars = event.characters, TrayGrid.isPrintableFilterInput(chars) else { return false }
            // Digits open a tile only before typing starts, so names with digits stay searchable.
            if state.query.isEmpty, let digit = Int(chars), (1...9).contains(digit) {
                if tiles.indices.contains(digit - 1) { openItem(tiles[digit - 1]) }
            } else {
                state.query += chars
                state.selection = 0
            }
        }
        return true
    }

    private func openItem(_ item: MenuBarItem) {
        close()
        model.trigger(item)
    }

    private func openSettings() {
        close()
        onOpenSettings?()
    }
}

private struct TrayView: View {
    @ObservedObject var model: ItemsModel
    @ObservedObject var prefs: Preferences
    @ObservedObject var state: TrayState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let open: (MenuBarItem) -> Void
    let openSettings: () -> Void
    let closeTray: () -> Void

    var body: some View {
        let tiles = TrayGrid.tiles(from: model.trayCandidates, query: state.query,
                                   openCounts: prefs.openCounts, pinned: prefs.pinned)
        let effectiveSelection = tiles.isEmpty ? 0 : min(max(state.selection, 0), tiles.count - 1)
        VStack(alignment: .leading, spacing: 10) {
            filterRow

            if !model.isTrusted {
                placeholder("lock.shield", "Accessibility access needed",
                            "MenuTuck reads and clicks menu bar icons through Accessibility.") {
                    Button("Grant Access…") {
                        closeTray()
                        model.requestTrust()
                    }.controlSize(.small)
                }
            } else if tiles.isEmpty, state.query.isEmpty {
                placeholder("tray", "Nothing tucked away", "⌘-drag an icon left of |› to tuck it here.") { EmptyView() }
            } else if tiles.isEmpty {
                placeholder("magnifyingglass", "No matches for “\(state.query)”", "esc clears the filter.") { EmptyView() }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(76), spacing: 4), count: TrayGrid.columns(for: tiles.count)), spacing: 4) {
                    ForEach(Array(tiles.enumerated()), id: \.element.id) { index, item in
                        tile(item, index: index, isSelected: index == effectiveSelection)
                    }
                }
            }

            Divider()
            footer
        }
        .padding(12)
        .frame(minWidth: 260)
        .fixedSize()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var filterRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            HStack(spacing: 1) {
                if !state.query.isEmpty { Text(state.query) }
                Rectangle().fill(Color.accentColor).frame(width: 1.5, height: 14)
                if state.query.isEmpty { Text("Filter hidden icons").foregroundStyle(.tertiary) }
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.query.isEmpty ? "Filter, empty. Type to filter." : "Filter: \(state.query)")
    }

    private func placeholder<Action: View>(_ symbol: String, _ title: String, _ hint: String,
                                           @ViewBuilder action: () -> Action) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.secondary)
            Text(title).font(.callout.weight(.medium))
            Text(hint).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            action()
        }
        .frame(maxWidth: .infinity, minHeight: 90)
        .frame(width: 236)
    }

    private var footer: some View {
        HStack {
            Text("↩ Open  ·  ⌘, Settings  ·  esc Close")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button(action: openSettings) { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Settings (⌘,)")
                .accessibilityLabel("Settings")
        }
    }

    private func badge(_ item: MenuBarItem) -> String? {
        item.bundleID.flatMap { state.badges[$0] }
    }

    private func tile(_ item: MenuBarItem, index: Int, isSelected: Bool) -> some View {
        let subtitle = item.detail == item.appName ? "" : item.detail
        return VStack(spacing: 3) {
            Image(nsImage: item.appIcon)
                .resizable()
                .frame(width: 32, height: 32)
                .saturation(item.isRunning ? 1 : 0)
                .opacity(item.isRunning ? 1 : 0.55)
                .overlay(alignment: .topTrailing) {
                    Group {
                        if let text = badge(item).map(TrayGrid.badgeText) {
                            Text(text)
                                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 14, minHeight: 14)
                                .background(.red, in: Capsule())
                        }
                    }
                    // Pulses when a badge appears or changes; badges are kept between opens, so an unchanged one stays still.
                    .phaseAnimator([1.0, reduceMotion ? 1.0 : 1.4, 1.0], trigger: badge(item)) { content, scale in
                        content.scaleEffect(scale)
                    } animation: { _ in .spring(duration: 0.25) }
                    .offset(x: 6, y: -4)
                }
            Text(item.appName)
                .font(.caption)
                .lineLimit(1)
            Text(subtitle.isEmpty ? " " : subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .frame(width: 76)
        .background(isSelected ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
        }
        .overlay(alignment: .topLeading) {
            if state.query.isEmpty, index < 9 {
                Text("\(index + 1)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 2) {
                if prefs.pinned.contains(item.storageKey) { Image(systemName: "pin.fill") }
                if prefs.alwaysHiddenEnabled && item.section == .alwaysHidden { Image(systemName: MenuSection.alwaysHidden.symbol) }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(4)
        }
        .contentShape(Rectangle())
        .onTapGesture { open(item) }
        .onHover { if $0 { state.selection = index } }
        .help(item.detail.isEmpty ? item.appName : "\(item.appName) — \(item.detail)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([item.appName, subtitle, badge(item).map { "badge \($0)" } ?? ""].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open(item) }
        .contextMenu { menu(for: item) }
    }

    @ViewBuilder
    private func menu(for item: MenuBarItem) -> some View {
        let effectiveSection = (item.section == .alwaysHidden && !prefs.alwaysHiddenEnabled) ? .hidden : item.section
        Button(item.isRunning ? "Open Menu" : "Open \(item.appName)") { open(item) }
        Button(prefs.pinned.contains(item.storageKey) ? "Unpin" : "Pin to Top") {
            prefs.pinned.formSymmetricDifference([item.storageKey])
        }
        Divider()
        ForEach(MenuSection.allCases.filter { $0 != effectiveSection && ($0 != .alwaysHidden || prefs.alwaysHiddenEnabled) }) { section in
            Button("Move to \(section.title)") { model.move(item, to: section) }
        }
        Divider()
        if let url = item.appURL {
            Button("Show in Finder") {
                closeTray()
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        if item.isRunning {
            Button("Quit \(item.appName)") { NSRunningApplication(processIdentifier: item.pid)?.terminate() }
        }
    }
}
