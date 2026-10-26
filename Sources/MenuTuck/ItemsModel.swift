import AppKit
import ApplicationServices

/// Data for the "Menu Bar Items" settings tab: scan, classify by dividers, move across dividers, and trigger.
final class ItemsModel: ObservableObject {
    @Published private(set) var items: [MenuBarItem] = []
    @Published private(set) var isBusy = false
    @Published private(set) var isTrusted = AXIsProcessTrusted()
    @Published var searchQuery = ""
    @Published var lastError: String?

    private weak var controller: SectionController?
    private let prefs = Preferences.shared
    private var cachedByID: [String: MenuBarItem] = [:]

    init(controller: SectionController) {
        self.controller = controller
    }

    func items(in section: MenuSection) -> [MenuBarItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            let effective = (item.section == .alwaysHidden && !prefs.alwaysHiddenEnabled) ? .hidden : item.section
            guard effective == section else { return false }
            guard !query.isEmpty else { return true }
            return item.appName.localizedCaseInsensitiveContains(query)
                || item.detail.localizedCaseInsensitiveContains(query)
        }
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
        let found = MenuBarScanner.scan()
        let ahEnabled = prefs.alwaysHiddenEnabled

        for scanned in found where scanned.frame.minY < 40 && scanned.frame.minX > 5 {
            let key = scanned.storageKey
            let detected = Self.sectionFromFrame(scanned.frame, layout: layout, alwaysHiddenEnabled: ahEnabled)
            let prevPhysical = prefs.lastPhysicalSection(for: key)
            prefs.setLastPhysicalSection(detected, for: key)

            if detected != .visible
                || prefs.sectionOverride(for: key) == nil
                || (prevPhysical != nil && prevPhysical != detected) {
                prefs.setSectionOverride(detected, for: key)
                for idx in items.indices where items[idx].storageKey == key {
                    items[idx].section = detected
                    cachedByID[items[idx].id]?.section = detected
                }
            }
        }
    }

    /// Scans menu bar items and classifies them relative to MenuTuck's dividers.
    /// - Parameter syncFromDividers: When `true` (when clicking "Sync Dividers"), forces all saved
    ///   section overrides to match the current physical divider positions.
    func refresh(syncFromDividers: Bool = false) {
        checkTrust()
        let layout = controller?.layout()
        let currentlyHidden = MenuBarHider.shared.currentlyHiddenBundleIDs
        let ahEnabled = prefs.alwaysHiddenEnabled
        isBusy = true

        DispatchQueue.global(qos: .userInitiated).async {
            let found = MenuBarScanner.scan()
            DispatchQueue.main.async {
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
                    let hasLiveFrame = item.isFromAX && !isHiddenByAssertion
                        && item.frame.minY < 40 && item.frame.minX > 5

                    if hasLiveFrame, let layout, layout.toggle.width > 0 {
                        let detected = Self.sectionFromFrame(item.frame, layout: layout, alwaysHiddenEnabled: ahEnabled)
                        let prevPhysical = self.prefs.lastPhysicalSection(for: key)
                        self.prefs.setLastPhysicalSection(detected, for: key)

                        // Rule 1: Any item physically to the left of `|›` or `‖` on screen is ALWAYS in that hidden section.
                        // Rule 2: If an item moved from left of `|›` to right of `|›` (prevPhysical != detected), update it.
                        if detected != .visible
                            || syncFromDividers
                            || self.prefs.sectionOverride(for: key) == nil
                            || (prevPhysical != nil && prevPhysical != detected) {
                            item.section = detected
                            self.prefs.setSectionOverride(detected, for: key)
                        } else if let saved = self.prefs.sectionOverride(for: key) {
                            item.section = saved
                        } else {
                            item.section = detected
                        }
                    } else if let saved = self.prefs.sectionOverride(for: key) {
                        item.section = saved
                    } else {
                        item.section = .visible
                    }
                    return item
                }
                self.isBusy = false
                self.controller?.apply()
            }
        }
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

    // MARK: - Move

    func move(_ item: MenuBarItem, to target: MenuSection) {
        guard item.section != target, !isBusy else { return }
        lastError = nil
        prefs.setSectionOverride(target, for: item.storageKey)

        for idx in items.indices where items[idx].storageKey == item.storageKey {
            items[idx].section = target
            cachedByID[items[idx].id]?.section = target
        }

        if target == .hidden, controller?.state != .collapsed {
            controller?.set(.collapsed)
        } else if target == .alwaysHidden, controller?.state == .showAll {
            controller?.set(.collapsed)
        } else {
            controller?.apply()
        }
    }
}
