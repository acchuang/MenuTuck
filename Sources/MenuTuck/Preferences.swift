import AppKit
import Combine

/// UserDefaults-backed settings, observable from SwiftUI and AppKit.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let autoHide = "autoHide"
        static let autoHideDelay = "autoHideDelay"
        static let alwaysHiddenEnabled = "alwaysHiddenEnabled"
        static let showDividers = "showDividers"
        static let enableGlobalHotkey = "enableGlobalHotkey"
        static let toggleShortcut = "toggleShortcut"
        static let showAllShortcut = "showAllShortcut"
        static let hoverReveal = "hoverReveal"
        static let newAppSection = "newAppSection"
        static let sectionOverrides = "sectionOverrides"
        static let revealStyle = "revealStyle"
        static let didOnboard = "didOnboard"
        static let openCounts = "openCounts"
        static let pinned = "pinned"
    }

    enum RevealStyle: String {
        /// Hidden icons open in a panel under the toggle; nothing in the bar moves.
        case tray
        /// Hidden icons slide back into the menu bar.
        case menuBar
    }

    private let defaults = UserDefaults.standard
    /// Where each item physically sat at its last scan. This launch only: divider positions don't survive a relaunch.
    private var lastPhysicalSections: [String: MenuSection] = [:]

    static let autoHideDelays: [Double] = [5, 15, 30]

    /// Collapse the hidden section after a delay, or on a click below the menu bar.
    @Published var autoHide: Bool { didSet { defaults.set(autoHide, forKey: Key.autoHide) } }
    /// Seconds before the hidden section collapses again; one of `autoHideDelays`.
    @Published var autoHideDelay: Double { didSet { defaults.set(autoHideDelay, forKey: Key.autoHideDelay) } }
    /// Use a third "always hidden" section (shown only with ⌥-click).
    @Published var alwaysHiddenEnabled: Bool { didSet { defaults.set(alwaysHiddenEnabled, forKey: Key.alwaysHiddenEnabled) } }
    /// Draw a thin divider between sections when they are expanded.
    @Published var showDividers: Bool { didSet { defaults.set(showDividers, forKey: Key.showDividers) } }
    /// Global shortcut that toggles hidden icons; nil when cleared. Clearing also writes the legacy
    /// on/off flag, which is what tells a cleared shortcut apart from one never customized (⌃⌥M).
    @Published var toggleShortcut: Shortcut? {
        didSet {
            defaults.set(toggleShortcut?.plist, forKey: Key.toggleShortcut)
            defaults.set(toggleShortcut != nil, forKey: Key.enableGlobalHotkey)
        }
    }
    /// Global shortcut that shows every icon, Always Hidden included. Unset by default.
    @Published var showAllShortcut: Shortcut? {
        didSet { defaults.set(showAllShortcut?.plist, forKey: Key.showAllShortcut) }
    }
    /// Expand the hidden section when the pointer rests on the `|›` toggle. Off by default: it needs a global mouse monitor.
    @Published var hoverReveal: Bool { didSet { defaults.set(hoverReveal, forKey: Key.hoverReveal) } }
    /// Where an app seen for the first time goes; nil leaves it where its icon lands in the menu bar.
    @Published var newAppSection: MenuSection? {
        didSet { defaults.set(newAppSection?.rawValue, forKey: Key.newAppSection) }
    }
    /// How a click on the toggle reveals hidden icons. Defaults to the Tray on a notched screen,
    /// where revealed icons would land behind the notch.
    @Published var revealStyle: RevealStyle { didSet { defaults.set(revealStyle.rawValue, forKey: Key.revealStyle) } }
    /// Finished the pick-icons onboarding. Anyone who already arranged icons counts as done.
    @Published var didOnboard: Bool { didSet { defaults.set(didOnboard, forKey: Key.didOnboard) } }
    /// Saved per-bundleID section assignments (`bundleID -> MenuSection.rawValue`).
    @Published var sectionOverrides: [String: String] {
        didSet { defaults.set(sectionOverrides, forKey: Key.sectionOverrides) }
    }
    /// Storage keys of items pinned to the top of the Tray.
    @Published var pinned: Set<String> { didSet { defaults.set(pinned.sorted(), forKey: Key.pinned) } }

    private init() {
        defaults.register(defaults: [
            Key.autoHide: true,
            Key.autoHideDelay: 15.0,
            Key.alwaysHiddenEnabled: true,
            Key.showDividers: true,
            Key.enableGlobalHotkey: true,
        ])
        autoHide = defaults.bool(forKey: Key.autoHide)
        let savedDelay = defaults.double(forKey: Key.autoHideDelay)
        autoHideDelay = Self.autoHideDelays.min { abs($0 - savedDelay) < abs($1 - savedDelay) } ?? 15
        alwaysHiddenEnabled = defaults.bool(forKey: Key.alwaysHiddenEnabled)
        showDividers = defaults.bool(forKey: Key.showDividers)
        if !defaults.bool(forKey: Key.enableGlobalHotkey) {
            toggleShortcut = nil
        } else {
            toggleShortcut = defaults.dictionary(forKey: Key.toggleShortcut).flatMap(Shortcut.init(plist:)) ?? .defaultToggle
        }
        showAllShortcut = defaults.dictionary(forKey: Key.showAllShortcut).flatMap(Shortcut.init(plist:))
        hoverReveal = defaults.bool(forKey: Key.hoverReveal)
        newAppSection = defaults.string(forKey: Key.newAppSection).flatMap(MenuSection.init(rawValue:))
        let hasNotch = NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
        revealStyle = defaults.string(forKey: Key.revealStyle).flatMap(RevealStyle.init(rawValue:))
            ?? (hasNotch ? .tray : .menuBar)
        let overrides = (defaults.dictionary(forKey: Key.sectionOverrides) as? [String: String]) ?? [:]
        sectionOverrides = overrides
        pinned = Set(defaults.stringArray(forKey: Key.pinned) ?? [])
        defaults.removeObject(forKey: "lastPhysicalSections") // persisted by older builds
        didOnboard = defaults.object(forKey: Key.didOnboard) as? Bool ?? !overrides.isEmpty
    }

    func sectionOverride(for key: String) -> MenuSection? {
        guard let raw = sectionOverrides[key] else { return nil }
        let section = MenuSection(rawValue: raw)
        if section == .alwaysHidden, !alwaysHiddenEnabled {
            return .hidden
        }
        return section
    }

    func setSectionOverride(_ section: MenuSection, for key: String) {
        guard sectionOverrides[key] != section.rawValue else { return }
        sectionOverrides[key] = section.rawValue
    }

    func setSectionOverrides(_ section: MenuSection, for keys: Set<String>) {
        var updated = sectionOverrides
        var changed = false
        for key in keys where updated[key] != section.rawValue {
            updated[key] = section.rawValue
            changed = true
        }
        if changed { sectionOverrides = updated }
    }

    func lastPhysicalSection(for key: String) -> MenuSection? { lastPhysicalSections[key] }

    func setLastPhysicalSection(_ section: MenuSection, for key: String) { lastPhysicalSections[key] = section }

    func bundleIDs(in sections: Set<MenuSection>) -> Set<String> {
        var result = Set<String>()
        for (key, raw) in sectionOverrides {
            guard var section = MenuSection(rawValue: raw) else { continue }
            if section == .alwaysHidden, !alwaysHiddenEnabled {
                section = .hidden
            }
            if sections.contains(section) {
                result.insert(key)
            }
        }
        return result
    }

    struct Layout: Codable, Equatable {
        var sections: [String: String]
        var alwaysHiddenEnabled: Bool
    }

    func exportLayout() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Layout(sections: sectionOverrides, alwaysHiddenEnabled: alwaysHiddenEnabled))
    }

    /// Merges a saved layout over the current one. Unknown section names are dropped. Returns how many items it set.
    @discardableResult
    func importLayout(_ data: Data) throws -> Int {
        let layout = try Self.parseLayout(data)
        sectionOverrides.merge(layout.sections) { _, new in new }
        if layout.alwaysHiddenEnabled { alwaysHiddenEnabled = true }
        return layout.sections.count
    }

    static func parseLayout(_ data: Data) throws -> Layout {
        var layout = try JSONDecoder().decode(Layout.self, from: data)
        layout.sections = layout.sections.filter { MenuSection(rawValue: $0.value) != nil }
        return layout
    }

    /// How often each item was opened, so the Tray can put favorites first.
    var openCounts: [String: Int] { defaults.dictionary(forKey: Key.openCounts) as? [String: Int] ?? [:] }

    func recordOpen(_ key: String) {
        var counts = openCounts
        counts[key, default: 0] += 1
        defaults.set(counts, forKey: Key.openCounts)
    }
}
