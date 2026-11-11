import AppKit
import ApplicationServices

/// Data for the "Menu Bar Items" settings tab: scan, classify by dividers, move across dividers, and trigger.
final class ItemsModel: ObservableObject {
    @Published private(set) var items: [MenuBarItem] = []
    @Published private(set) var isBusy = false
    @Published private(set) var isTrusted = AXIsProcessTrusted()
    @Published var searchQuery = ""
    @Published var lastError: String?
    @Published private(set) var didJustSync = false

    private weak var controller: SectionController?
    private let prefs = Preferences.shared
    private var cachedByID: [String: MenuBarItem] = [:]
    private var syncFeedbackWorkItem: DispatchWorkItem?

    init(controller: SectionController) {
        self.controller = controller
    }

    func dismissError() {
        lastError = nil
    }

    func items(in section: MenuSection) -> [MenuBarItem] {
        items.filter { item in
            let effective = (item.section == .alwaysHidden && !prefs.alwaysHiddenEnabled) ? .hidden : item.section
            return effective == section && item.matches(searchQuery)
        }
    }

    /// Live items plus tucked apps that aren't running, which the Tray shows as grey tiles.
    var trayCandidates: [MenuBarItem] {
        let listed = Set(items.map(\.storageKey))
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let offline = prefs.bundleIDs(in: [.hidden, .alwaysHidden]).subtracting(listed).subtracting(running).sorted()
            .compactMap { id -> MenuBarItem? in
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
                return MenuBarItem(
                    id: "offline:\(id)", pid: 0, childIndex: 0,
                    appName: url.deletingPathExtension().lastPathComponent, bundleID: id,
                    detail: "Not running", frame: .zero, isFromAX: false,
                    section: prefs.sectionOverride(for: id) ?? .hidden
                )
            }
        return items + offline
    }

    /// Visible items macOS draws nowhere because the notch covers them.
    var underNotch: [MenuBarItem] {
        // ponytail: checks the first notched screen only; per-screen check if multi-notch setups show up.
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return [] }
        return Self.underNotch(items, notch: left.maxX...right.minX)
    }

    static func underNotch(_ items: [MenuBarItem], notch: ClosedRange<CGFloat>) -> [MenuBarItem] {
        items.filter { $0.section == .visible && $0.isFromAX && $0.frame.width > 0 && notch.contains($0.frame.midX) }
    }

    // MARK: - Permission

    func checkTrust() {
        isTrusted = AXIsProcessTrusted()
    }

    func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        if !isTrusted,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Scan

    /// Synchronously scans live AX positions right before collapsing the menu bar so any `⌘`-drags
    /// performed while expanded take effect immediately before `MenuBarHider` hides the items.
    func syncBeforeCollapse() {
        guard AXIsProcessTrusted(), let layout = controller?.layout(), layout.toggle.width > 0 else { return }
        // Known item owners only: a full scan here stalls the main thread. New apps arrive via refresh().
        let knownPIDs = Set(cachedByID.values.map(\.pid))
        let found = MenuBarScanner.scan(onlyPIDs: knownPIDs.isEmpty ? nil : knownPIDs)
        let ahEnabled = prefs.alwaysHiddenEnabled

        for scanned in found where scanned.frame.isOnMenuBar {
            let key = scanned.storageKey
            let detected = Self.sectionFromFrame(scanned.frame, layout: layout, alwaysHiddenEnabled: ahEnabled)
            if let section = reassign(key, detected: detected) {
                for idx in items.indices where items[idx].storageKey == key {
                    items[idx].section = section
                    cachedByID[items[idx].id]?.section = section
                }
            }
        }
    }

    /// Scans menu bar items and classifies them relative to MenuTuck's dividers.
    /// - Parameter syncFromDividers: When `true` (when clicking "Rescan Menu Bar"), forces all saved
    ///   section overrides to match the current physical divider positions.
    func refresh(syncFromDividers: Bool = false) {
        checkTrust()
        let layout = controller?.layout()
        let currentlyHidden = MenuBarHider.shared.currentlyHiddenBundleIDs
        let ahEnabled = prefs.alwaysHiddenEnabled
        isBusy = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = MenuBarScanner.scan()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let runningPIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
                self.cachedByID = self.cachedByID.filter { runningPIDs.contains($0.value.pid) }
                for item in found {
                    self.cachedByID[item.id] = item
                }

                let merged = Array(self.cachedByID.values).sorted { $0.frame.minX < $1.frame.minX }
                self.items = merged.map { item in
                    var item = item
                    let key = item.storageKey
                    let isHiddenByAssertion = currentlyHidden.contains(key)
                    let hasLiveFrame = item.isFromAX && !isHiddenByAssertion && item.frame.isOnMenuBar

                    if hasLiveFrame, let layout, layout.toggle.width > 0 {
                        let detected = Self.sectionFromFrame(item.frame, layout: layout, alwaysHiddenEnabled: ahEnabled)
                        item.section = self.reassign(key, detected: detected, force: syncFromDividers)
                            ?? self.prefs.sectionOverride(for: key) ?? detected
                    } else if let saved = self.prefs.sectionOverride(for: key) {
                        item.section = saved
                    } else {
                        // No frame to classify (no Accessibility access, or off the bar). Saved, so that
                        // changing "New apps go to" later only affects apps that show up after the change.
                        item.section = self.prefs.newAppSection ?? .visible
                        self.prefs.setSectionOverride(item.section, for: key)
                    }
                    return item
                }
                self.isBusy = false
                if syncFromDividers {
                    self.syncFeedbackWorkItem?.cancel()
                    self.didJustSync = true
                    let work = DispatchWorkItem { [weak self] in
                        self?.didJustSync = false
                    }
                    self.syncFeedbackWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
                }
                self.controller?.apply()
            }
        }
    }

    /// Records where an item physically sits and saves a new assignment if it needs one.
    /// Returns nil when the saved assignment stands.
    private func reassign(_ key: String, detected: MenuSection, force: Bool = false) -> MenuSection? {
        let section = Self.newAssignment(
            detected: detected,
            saved: prefs.sectionOverride(for: key),
            lastPhysical: prefs.lastPhysicalSection(for: key),
            newAppSection: prefs.newAppSection,
            force: force
        )
        prefs.setLastPhysicalSection(detected, for: key)
        if let section { prefs.setSectionOverride(section, for: key) }
        return section
    }

    /// An item is reassigned when the user asks for a full divider sync, when it is new, or when it
    /// physically crossed a divider (which includes a first sighting outside Visible).
    static func newAssignment(
        detected: MenuSection,
        saved: MenuSection?,
        lastPhysical: MenuSection?,
        newAppSection: MenuSection?,
        force: Bool
    ) -> MenuSection? {
        if force { return detected }
        if saved == nil, lastPhysical == nil, let newAppSection { return newAppSection }
        let moved = lastPhysical == nil ? detected != .visible : lastPhysical != detected
        return moved || saved == nil ? detected : nil
    }

    private static func sectionFromFrame(
        _ frame: CGRect,
        layout: DividerLayout,
        alwaysHiddenEnabled: Bool
    ) -> MenuSection {
        if frame.midX >= layout.toggle.midX { return .visible }
        if alwaysHiddenEnabled,
           let ah = layout.alwaysHidden,
           ah.width > 0,
           ah.midX < layout.toggle.minX,
           frame.midX < ah.midX {
            return .alwaysHidden
        }
        return .hidden
    }

    // MARK: - Trigger

    func trigger(_ item: MenuBarItem) {
        guard item.isRunning else { return launchAndOpen(item) }
        checkTrust()
        guard isTrusted else {
            requestTrust()
            lastError = "Grant Accessibility access to remotely click menu bar icons."
            return
        }
        lastError = nil
        if item.section == .alwaysHidden {
            controller?.set(.showAll)
        } else if item.section == .hidden, controller?.state == .collapsed {
            controller?.set(.expanded)
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.18) {
            let ok = MenuBarScanner.press(item)
            if !ok {
                DispatchQueue.main.async {
                    self.lastError = "Could not open \(item.appName) via Accessibility."
                }
            }
        }
    }

    private func launchAndOpen(_ item: MenuBarItem) {
        guard let url = item.appURL else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error {
                    self?.lastError = "Could not launch \(item.appName): \(error.localizedDescription)"
                } else {
                    self?.openWhenListed(item.storageKey, tries: 10)
                }
            }
        }
    }

    /// A freshly launched app takes a moment to put up its status item.
    private func openWhenListed(_ key: String, tries: Int) {
        if let live = items.first(where: { $0.storageKey == key }) { return trigger(live) }
        guard tries > 0 else { return }
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.openWhenListed(key, tries: tries - 1)
        }
    }

    // MARK: - Move

    func move(_ item: MenuBarItem, to target: MenuSection) {
        guard item.section != target, !isBusy else { return }
        lastError = nil
        prefs.setSectionOverride(target, for: item.storageKey)

        for idx in items.indices where items[idx].storageKey == item.storageKey {
            items[idx].section = target
            cachedByID[items[idx].id]?.section = target
        }

        controller?.apply()
    }
}
