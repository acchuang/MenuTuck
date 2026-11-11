import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var sections: SectionController
    @ObservedObject var model: ItemsModel

    var body: some View {
        TabView {
            ItemsTab(prefs: prefs, model: model)
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
    @ObservedObject var model: ItemsModel
    private let trustTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    /// Left to right, the way they sit in the menu bar.
    private var columns: [MenuSection] {
        prefs.alwaysHiddenEnabled ? [.alwaysHidden, .hidden, .visible] : [.hidden, .visible]
    }

    @State private var onboardingDone = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.isTrusted {
                OnboardingPermissionView(onRequestTrust: { model.requestTrust() })
            } else if !prefs.didOnboard {
                if onboardingDone {
                    OnboardingDoneView(model: model) { prefs.didOnboard = true }
                } else {
                    OnboardingPickView(model: model) { onboardingDone = true }
                }
            } else {
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

                NotchBanner(model: model)

                HStack(alignment: .top, spacing: 8) {
                    ForEach(columns) { section in
                        ArrangeColumn(model: model, section: section, targets: columns)
                    }
                }
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
                Text("Drag icons between columns or right-click one. ⌘-dragging in the menu bar works too.")
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
}

/// Visible icons the notch covers: macOS draws them nowhere, so offer to tuck them into the Tray.
private struct NotchBanner: View {
    @ObservedObject var model: ItemsModel

    var body: some View {
        let covered = model.underNotch
        if !covered.isEmpty {
            HStack(spacing: 8) {
                Label(
                    "\(covered.count == 1 ? "1 icon is" : "\(covered.count) icons are") under the notch: \(covered.map(\.appName).joined(separator: ", "))",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout)
                .foregroundStyle(.orange)
                .lineLimit(2)
                Spacer()
                Button("Move to Hidden") {
                    for item in covered { model.move(item, to: .hidden) }
                }
                .help("Hidden icons open from the Tray, which the notch never covers")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

private struct ArrangeColumn: View {
    @ObservedObject var model: ItemsModel
    let section: MenuSection
    let targets: [MenuSection]
    @State private var isTargeted = false

    var body: some View {
        let items = model.items(in: section)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label(section.title, systemImage: section.symbol)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(items.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            ScrollView {
                LazyVStack(spacing: 2) {
                    if items.isEmpty {
                        Text(model.searchQuery.isEmpty ? "Drag icons here" : "No matches")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    ForEach(items) { item in
                        ArrangeTile(item: item, targets: targets.filter { $0 != section }, model: model)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            isTargeted ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .dropDestination(for: String.self) { keys, _ in
            let dropped = model.items.filter { keys.contains($0.storageKey) }
            for item in dropped { model.move(item, to: section) }
            return !dropped.isEmpty
        } isTargeted: { isTargeted = $0 }
    }
}

private struct ArrangeTile: View {
    let item: MenuBarItem
    let targets: [MenuSection]
    let model: ItemsModel

    private var subtitle: String? {
        let trimmed = item.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "MenuBarExtra" || trimmed == item.appName ? nil : trimmed
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: item.appIcon)
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.appName)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .draggable(item.storageKey) {
            Image(nsImage: item.appIcon).resizable().frame(width: 24, height: 24)
        }
        .onTapGesture(count: 2) { model.trigger(item) }
        .help("Double-click to open \(item.appName)’s menu. Drag to another column to move it.")
        .contextMenu {
            Button("Open Menu") { model.trigger(item) }
            Divider()
            ForEach(targets) { target in
                Button("Move to \(target.title)") { model.move(item, to: target) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Open Menu") { model.trigger(item) }
        .accessibilityActions {
            ForEach(targets) { target in
                Button("Move to \(target.title)") { model.move(item, to: target) }
            }
        }
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

            Section("Reveal") {
                Picker("Clicking |‹ shows hidden icons", selection: $prefs.revealStyle) {
                    Text("In a Tray below the menu bar").tag(Preferences.RevealStyle.tray)
                    Text("In the menu bar").tag(Preferences.RevealStyle.menuBar)
                }
                Text("The Tray keeps icons out from behind the notch. Type to filter, 1–9 or Return to open, right-click a tile to move it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Hide again", selection: autoHideChoice) {
                    Text("Never").tag(0.0)
                    ForEach(Preferences.autoHideDelays, id: \.self) { Text("After \(Int($0)) s").tag($0) }
                }
                Text("Also hides when you click outside the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("New apps go to", selection: $prefs.newAppSection) {
                    Text("Where their icon lands").tag(MenuSection?.none)
                    Text("Visible").tag(MenuSection?.some(.visible))
                    Text("Hidden").tag(MenuSection?.some(.hidden))
                }
                Toggle("Use an Always Hidden section", isOn: $prefs.alwaysHiddenEnabled)
            }

            if prefs.revealStyle == .menuBar {
                Section("In the Menu Bar") {
                    Toggle("Show dividers (|› and ‖) when expanded", isOn: $prefs.showDividers)
                    Toggle("Reveal while hovering over |›", isOn: $prefs.hoverReveal)
                }
            }

            Section {
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

            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev build")
                Button("Check for Updates…") { UpdateChecker.run() }
                DisclosureGroup("macOS 27 notes") {
                    Text("Control Center items (Wi-Fi, Battery, Clock) can't be hidden. Apps with several menu bar icons hide all of them together.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// 0 means auto-hide is off; any other value is the delay.
    private var autoHideChoice: Binding<Double> {
        Binding(
            get: { prefs.autoHide ? prefs.autoHideDelay : 0 },
            set: { value in
                prefs.autoHide = value > 0
                if value > 0 { prefs.autoHideDelay = value }
            }
        )
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
