import AppKit
import SwiftUI

/// Pure grid logic for the Tray, kept apart so it can be tested.
enum TrayGrid {
    static let columns = 5

    /// Hidden first, then Always Hidden, each left to right as they sit in the bar.
    static func tiles(from items: [MenuBarItem], query: String) -> [MenuBarItem] {
        let tucked = items.filter { $0.section != .visible && $0.matches(query) }
        return tucked.filter { $0.section == .hidden } + tucked.filter { $0.section == .alwaysHidden }
    }

    /// Arrow-key move in a grid of `count` tiles. Stays put at an edge.
    static func move(_ index: Int, keyCode: UInt16, count: Int) -> Int {
        let target: Int
        switch keyCode {
        case 123: target = index - 1
        case 124: target = index + 1
        case 125: target = index + columns
        case 126: target = index - columns
        default: return index
        }
        return (0..<count).contains(target) ? target : index
    }
}

final class TrayState: ObservableObject {
    @Published var query = ""
    @Published var selection = 0
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
        // ponytail: full AX rescan per open keeps tile text live; scan only tucked PIDs if it ever lags.
        model.refresh()

        let view = TrayView(model: model, prefs: .shared, state: state) { [weak self] in self?.openItem($0) }
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
        let tiles = TrayGrid.tiles(from: model.items, query: state.query)
        switch event.keyCode {
        case 53: // Esc
            close()
        case 36, 76: // Return, keypad Enter
            if tiles.indices.contains(state.selection) { openItem(tiles[state.selection]) }
        case 51: // Delete
            guard !state.query.isEmpty else { return true }
            state.query.removeLast()
            state.selection = 0
        case 123...126:
            state.selection = TrayGrid.move(state.selection, keyCode: event.keyCode, count: tiles.count)
        default:
            guard event.modifierFlags.isDisjoint(with: [.command, .control]),
                  let chars = event.characters, !chars.isEmpty,
                  chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return false }
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
}

private struct TrayView: View {
    @ObservedObject var model: ItemsModel
    @ObservedObject var prefs: Preferences
    @ObservedObject var state: TrayState
    let open: (MenuBarItem) -> Void

    var body: some View {
        let tiles = TrayGrid.tiles(from: model.items, query: state.query)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                Text(state.query.isEmpty ? "Type to filter" : state.query)
                    .foregroundStyle(state.query.isEmpty ? .secondary : .primary)
                Spacer(minLength: 0)
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            if !model.isTrusted {
                Button("Grant Accessibility Access…") { model.requestTrust() }
            } else if tiles.isEmpty {
                Text(state.query.isEmpty ? "No hidden icons. ⌘-drag an icon left of |› to tuck it here." : "No matches")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(76), spacing: 4), count: min(tiles.count, TrayGrid.columns)), spacing: 4) {
                    ForEach(Array(tiles.enumerated()), id: \.element.id) { index, item in
                        tile(item, index: index)
                    }
                }
            }
        }
        .padding(12)
        .frame(minWidth: 240)
        .fixedSize()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func tile(_ item: MenuBarItem, index: Int) -> some View {
        let subtitle = item.detail == item.appName ? "" : item.detail
        return VStack(spacing: 3) {
            Image(nsImage: item.appIcon)
                .resizable()
                .frame(width: 32, height: 32)
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
        .background(index == state.selection ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topLeading) {
            if state.query.isEmpty, index < 9 {
                Text("\(index + 1)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
        }
        .overlay(alignment: .topTrailing) {
            if item.section == .alwaysHidden {
                Image(systemName: MenuSection.alwaysHidden.symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { open(item) }
        .onHover { if $0 { state.selection = index } }
        .help(item.detail.isEmpty ? item.appName : "\(item.appName) — \(item.detail)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(subtitle.isEmpty ? item.appName : "\(item.appName), \(subtitle)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open(item) }
        .contextMenu { menu(for: item) }
    }

    @ViewBuilder
    private func menu(for item: MenuBarItem) -> some View {
        Button("Open Menu") { open(item) }
        Divider()
        ForEach(MenuSection.allCases.filter { $0 != item.section && ($0 != .alwaysHidden || prefs.alwaysHiddenEnabled) }) { section in
            Button("Move to \(section.title)") { model.move(item, to: section) }
        }
        Divider()
        if let url = NSRunningApplication(processIdentifier: item.pid)?.bundleURL {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        Button("Quit \(item.appName)") { NSRunningApplication(processIdentifier: item.pid)?.terminate() }
    }
}
