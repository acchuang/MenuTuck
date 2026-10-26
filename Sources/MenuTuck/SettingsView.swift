import AppKit
import Combine
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
            GeneralTab(prefs: prefs)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .padding(.top, 8)
        .frame(minWidth: 560, minHeight: 520)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.isTrusted {
                PermissionBanner(model: model)
            }

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter menu bar items…", text: $model.searchQuery)
                        .textFieldStyle(.plain)
                    if !model.searchQuery.isEmpty {
                        Button {
                            model.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

                Picker(
                    "Menu Bar",
                    selection: Binding(
                        get: { sections.state },
                        set: { newState in
                            DispatchQueue.main.async {
                                sections.set(newState)
                            }
                        }
                    )
                ) {
                    ForEach(availableStates) { state in
                        Text(state.label).tag(state)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: prefs.alwaysHiddenEnabled ? 230 : 160)
                .help("Toggle whether hidden menu bar icons and dividers (|, ‖) are shown")
            }

            List {
                ForEach(activeSections) { section in
                    Section {
                        let items = model.items(in: section)
                        if items.isEmpty {
                            Text("No icons in this section")
                                .foregroundStyle(.tertiary)
                        }
                        ForEach(items) { item in
                            ItemRow(
                                item: item,
                                sections: activeSections,
                                disabled: model.isBusy,
                                onTrigger: { model.trigger(item) },
                                onMove: { target in model.move(item, to: target) }
                            )
                        }
                    } header: {
                        HStack {
                            Label(section.title, systemImage: section.symbol)
                            Spacer()
                            Text("\(model.items(in: section).count)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                Text("⌘-drag icons left of | (Hidden) or ‖ (Always Hidden) in the menu bar, or choose a section above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
                Button("Sync Dividers") { model.refresh(syncFromDividers: true) }
                    .disabled(model.isBusy)
                    .help("Re-scan the menu bar and assign sections based on the | and ‖ divider positions")
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

private struct ItemRow: View {
    let item: MenuBarItem
    let sections: [MenuSection]
    let disabled: Bool
    let onTrigger: () -> Void
    let onMove: (MenuSection) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: Self.icon(for: item.pid))
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.appName)
                    .fontWeight(.medium)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button("Click", action: onTrigger)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open or click this menu bar item")
                .disabled(disabled)
            Picker(
                "Section",
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
            .frame(width: 140)
            .disabled(disabled)
        }
        .padding(.vertical, 2)
    }

    private static func icon(for pid: pid_t) -> NSImage {
        NSRunningApplication(processIdentifier: pid)?.icon
            ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
            ?? NSImage()
    }
}

private struct PermissionBanner: View {
    @ObservedObject var model: ItemsModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Allow Accessibility access for live divider dragging").font(.headline)
                Text("Grant Accessibility so MenuTuck can detect live ⌘-drags across the | and ‖ dividers and move icons across dividers.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Accessibility Settings") { model.requestTrust() }
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var prefs: Preferences
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Behavior") {
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
                Toggle("Show dividers (| and ‖) when expanded", isOn: $prefs.showDividers)
                Toggle("Use an “Always Hidden” section (‖)", isOn: $prefs.alwaysHiddenEnabled)
                Toggle("Global shortcut (⌃⌥M) to toggle hidden icons", isOn: $prefs.enableGlobalHotkey)
            }

            Section("How to use") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• Click ‹ in the menu bar to expand and show the | (Hidden) and ‖ (Always Hidden) dividers.")
                    Text("• Hold ⌘ and drag any menu bar icon to the left of | to hide it, or to the left of ‖ to always hide it.")
                    Text("• You can also ⌘-drag the | or ‖ dividers themselves, or pick a section in Menu Bar Items.")
                    Text("• Click ‖ (or ⌥-click ›) to reveal Always Hidden icons.")
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
