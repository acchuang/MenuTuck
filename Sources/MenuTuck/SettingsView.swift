import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var sections: SectionController
    @ObservedObject var model: ItemsModel

    var body: some View {
        TabView {
            ItemsTab(prefs: prefs, sections: sections, model: model)
                .tabItem { Label("Menu Bar Items", systemImage: "menubar.rectangle") }
            GeneralTab(prefs: prefs, sections: sections)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .padding(.top, 8)
        .frame(minWidth: 600, minHeight: 540)
    }
}

// MARK: - Items

private struct ItemsTab: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var sections: SectionController
    @ObservedObject var model: ItemsModel
    private let trustTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private var activeSections: [MenuSection] {
        prefs.alwaysHiddenEnabled ? MenuSection.allCases : [.visible, .hidden]
    }

    private var availableStates: [BarState] {
        prefs.alwaysHiddenEnabled ? BarState.allCases : [.collapsed, .expanded]
    }

    private var totalMatchingItems: Int {
        activeSections.reduce(0) { $0 + model.items(in: $1).count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MenuBarPostureBar(
                state: sections.state,
                availableStates: availableStates,
                alwaysHiddenEnabled: prefs.alwaysHiddenEnabled,
                onSelectState: { newState in
                    DispatchQueue.main.async {
                        sections.set(newState)
                    }
                }
            )

            if model.isTrusted {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter menu bar items…", text: $model.searchQuery)
                        .textFieldStyle(.plain)
                        .accessibilityLabel("Filter menu bar items")
                    if !model.searchQuery.isEmpty {
                        Button {
                            model.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear filter")
                        .accessibilityLabel("Clear filter")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

                if !model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   totalMatchingItems == 0 {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No menu bar items matching “\(model.searchQuery)”")
                            .font(.headline)
                        Button("Clear Filter") {
                            model.searchQuery = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    List {
                        ForEach(activeSections) { section in
                            Section {
                                let sectionItems = model.items(in: section)
                                if sectionItems.isEmpty {
                                    Text(emptySectionMessage(for: section))
                                        .foregroundStyle(.tertiary)
                                }
                                ForEach(sectionItems) { item in
                                    ItemRow(
                                        item: item,
                                        sections: activeSections,
                                        disabled: model.isBusy,
                                        onTrigger: { model.trigger(item) },
                                        onMove: { target in model.move(item, to: target) }
                                    )
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Label(section.title, systemImage: section.symbol)
                                        .fontWeight(.semibold)
                                    Text(section.spatialHint)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(.quaternary.opacity(0.6), in: Capsule())
                                    Spacer()
                                    Text("\(model.items(in: section).count)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }
            } else {
                OnboardingPermissionView(
                    alwaysHiddenEnabled: prefs.alwaysHiddenEnabled,
                    onRequestTrust: { model.requestTrust() }
                )
            }

            if let error = model.lastError {
                HStack(spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button {
                        model.dismissError()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss error")
                    .accessibilityLabel("Dismiss error")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 8) {
                Text("Hold ⌘ and drag icons across |› or ‖ in the menu bar, or assign a section above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isBusy {
                    ProgressView().controlSize(.small)
                } else if model.didJustSync {
                    Label("Synced", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Rescan Menu Bar") { model.refresh(syncFromDividers: true) }
                    .disabled(model.isBusy || !model.isTrusted)
                    .help("Re-scan the menu bar and sync sections from the current |› and ‖ divider positions")
            }
        }
        .padding()
        .onReceive(trustTimer) { _ in
            guard !model.isTrusted else { return }
            model.checkTrust()
            if model.isTrusted { model.refresh(syncFromDividers: true) }
        }
    }

    private func emptySectionMessage(for section: MenuSection) -> String {
        switch section {
        case .visible:
            return "No visible icons — assign an item to Visible or ⌘-drag it right of |›"
        case .hidden:
            return "No hidden icons — choose Hidden on an item or ⌘-drag it left of |›"
        case .alwaysHidden:
            return "No always-hidden icons — choose Always Hidden on an item or ⌘-drag it left of ‖"
        }
    }
}

/// Top bar showing the physical left-to-right menu bar layout (`[Always Hidden] ‖ [Hidden] |› [Visible]`)
/// alongside the global menu bar state switcher (`Collapsed`, `Expanded`, `Show All`).
private struct MenuBarPostureBar: View {
    let state: BarState
    let availableStates: [BarState]
    let alwaysHiddenEnabled: Bool
    let onSelectState: (BarState) -> Void

    private var toggleGlyph: String {
        state == .collapsed ? "|‹" : "|›"
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Menu Bar Layout (left → right)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    if alwaysHiddenEnabled {
                        sectionPill("Always Hidden", isShownOnBar: state == .showAll)
                        dividerBadge("‖", isShownOnBar: state != .collapsed)
                    }
                    sectionPill("Hidden", isShownOnBar: state != .collapsed)
                    dividerBadge(toggleGlyph, isShownOnBar: true)
                    sectionPill("Visible", isShownOnBar: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                alwaysHiddenEnabled
                    ? "Menu bar layout from left to right: Always Hidden, double bar divider, Hidden, toggle divider, Visible"
                    : "Menu bar layout from left to right: Hidden, toggle divider, Visible"
            )

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("Menu Bar State")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Picker(
                    "Menu Bar State",
                    selection: Binding(get: { state }, set: onSelectState)
                ) {
                    ForEach(availableStates) { itemState in
                        Text(itemState.label).tag(itemState)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Switch the live menu bar between Collapsed, Expanded, and Show All")
                .accessibilityLabel("Menu Bar State")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private func sectionPill(_ title: String, isShownOnBar: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isShownOnBar ? Color.accentColor : Color.secondary.opacity(0.35))
                .frame(width: 5, height: 5)
            Text(title)
                .font(.caption2.weight(isShownOnBar ? .medium : .regular))
                .foregroundStyle(isShownOnBar ? .primary : .secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            isShownOnBar ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 5)
        )
    }

    private func dividerBadge(_ glyph: String, isShownOnBar: Bool) -> some View {
        Text(glyph)
            .font(.caption2.monospaced().weight(.semibold))
            .foregroundStyle(isShownOnBar ? .primary : .tertiary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
    }
}

private struct ItemRow: View {
    let item: MenuBarItem
    let sections: [MenuSection]
    let disabled: Bool
    let onTrigger: () -> Void
    let onMove: (MenuSection) -> Void

    private static var iconCache: [pid_t: NSImage] = [:]

    private var subtitleText: String? {
        let trimmed = item.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != "MenuBarExtra", trimmed != item.appName {
            return trimmed
        }
        if let bid = item.bundleID, bid != item.appName {
            return bid
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: Self.icon(for: item.pid))
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.appName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if let subtitleText {
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button("Open Menu", action: onTrigger)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Expand the menu bar if needed and click \(item.appName)’s status item")
                .accessibilityLabel("Open \(item.appName) menu bar item")
                .disabled(disabled)
            Picker(
                "Section for \(item.appName)",
                selection: Binding(
                    get: { item.section },
                    set: { target in
                        DispatchQueue.main.async {
                            onMove(target)
                        }
                    }
                )
            ) {
                ForEach(sections) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(minWidth: 135)
            .fixedSize()
            .accessibilityLabel("Section for \(item.appName)")
            .disabled(disabled)
        }
        .padding(.vertical, 2)
    }

    private static func icon(for pid: pid_t) -> NSImage {
        if let cached = iconCache[pid] {
            return cached
        }
        if let appIcon = NSRunningApplication(processIdentifier: pid)?.icon {
            iconCache[pid] = appIcon
            return appIcon
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var sections: SectionController
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            if !MenuBarHider.shared.isSupported {
                Section {
                    Label("This macOS doesn't provide the menu bar API MenuTuck needs. Icons won't be hidden.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section("Auto-Hide") {
                Toggle("Hide icons again automatically", isOn: $prefs.autoHide)
                LabeledContent("Hide after") {
                    HStack {
                        Slider(value: $prefs.autoHideDelay, in: 3...60, step: 1)
                            .frame(width: 180)
                        Text("\(Int(prefs.autoHideDelay)) s")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                .disabled(!prefs.autoHide)
                Toggle("Hide when clicking outside the menu bar", isOn: $prefs.rehideOnOutsideClick)
                Toggle("Reveal hidden icons while hovering over |›, until the pointer leaves the menu bar", isOn: $prefs.hoverReveal)
            }

            Section("Sections & Dividers") {
                Toggle("Show dividers (|› and ‖) when expanded", isOn: $prefs.showDividers)
                Toggle("Use an “Always Hidden” section (‖)", isOn: $prefs.alwaysHiddenEnabled)
                Picker("New apps go to", selection: $prefs.newAppSection) {
                    Text("Where their icon lands").tag(MenuSection?.none)
                    Text("Visible").tag(MenuSection?.some(.visible))
                    Text("Hidden").tag(MenuSection?.some(.hidden))
                }
            }

            Section("Shortcuts & Startup") {
                ShortcutRecorder(
                    title: "Toggle hidden icons", shortcut: $prefs.toggleShortcut, taken: prefs.showAllShortcut,
                    refused: sections.refusedHotkeys.contains(SectionController.toggleHotkeyID)
                )
                ShortcutRecorder(
                    title: "Show all icons", shortcut: $prefs.showAllShortcut, taken: prefs.toggleShortcut,
                    refused: sections.refusedHotkeys.contains(SectionController.showAllHotkeyID)
                )
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev build")
                Button("Check for Updates…") { UpdateChecker.run() }
            }

            Section("Quick Reference") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• Click |‹ in the menu bar to expand and show Hidden icons.")
                    Text("• Option-click (⌥-click) |‹ or click ‖ to Show All icons (including Always Hidden).")
                    Text("• Hold ⌘ and drag any menu bar icon left of |› (Hidden) or left of ‖ (Always Hidden).")
                    Text("• Right-click |‹ or ‖ in the menu bar to open the quick menu.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// A row that records a global shortcut: click, press the combo. Esc cancels, the × button clears.
private struct ShortcutRecorder: View {
    let title: String
    @Binding var shortcut: Shortcut?
    /// The other row's combo, which this one may not reuse.
    let taken: Shortcut?
    let refused: Bool
    @State private var monitor: Any?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                if refused {
                    Label("In use by another app", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button(monitor != nil ? "Press shortcut…" : shortcut?.label ?? "Record Shortcut") {
                    monitor == nil ? start() : stop()
                }
                .frame(minWidth: 120)
                .accessibilityLabel("\(title) shortcut")
                .accessibilityValue(monitor != nil ? "Recording" : shortcut?.label ?? "None")
                if shortcut != nil {
                    Button { shortcut = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Clear \(title) shortcut")
                }
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stop()
            } else if let recorded = Shortcut(event: event), recorded != taken {
                shortcut = recorded
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
