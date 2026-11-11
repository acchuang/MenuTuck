import Foundation
import Combine

/// UserDefaults-backed settings, observable from SwiftUI and AppKit.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let autoHide = "autoHide"
        static let autoHideDelay = "autoHideDelay"
        static let rehideOnOutsideClick = "rehideOnOutsideClick"
        static let alwaysHiddenEnabled = "alwaysHiddenEnabled"
        static let showDividers = "showDividers"
        static let enableGlobalHotkey = "enableGlobalHotkey"
        static let toggleShortcut = "toggleShortcut"
        static let showAllShortcut = "showAllShortcut"
        static let hoverReveal = "hoverReveal"
        static let newAppSection = "newAppSection"
        static let sectionOverrides = "sectionOverrides"
        static let lastPhysicalSections = "lastPhysicalSections"
    }

    private let defaults = UserDefaults.standard
    private var lastPhysicalSections: [String: String]

    /// Collapse the hidden section again after a delay.
    @Published var autoHide: Bool { didSet { defaults.set(autoHide, forKey: Key.autoHide) } }
    /// Seconds before the hidden section collapses again.
    @Published var autoHideDelay: Double { didSet { defaults.set(autoHideDelay, forKey: Key.autoHideDelay) } }
    /// Collapse the hidden section when the user clicks below the menu bar.
    @Published var rehideOnOutsideClick: Bool {
        didSet { defaults.set(rehideOnOutsideClick, forKey: Key.rehideOnOutsideClick) }
    }
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
    /// Saved per-bundleID section assignments (`bundleID -> MenuSection.rawValue`).
    @Published var sectionOverrides: [String: String] {
        didSet { defaults.set(sectionOverrides, forKey: Key.sectionOverrides) }
    }

    private init() {
        defaults.register(defaults: [
            Key.autoHide: true,
            Key.autoHideDelay: 10.0,
            Key.rehideOnOutsideClick: false,
            Key.alwaysHiddenEnabled: true,
            Key.showDividers: true,
            Key.enableGlobalHotkey: true,
        ])
        autoHide = defaults.bool(forKey: Key.autoHide)
        autoHideDelay = defaults.double(forKey: Key.autoHideDelay)
        rehideOnOutsideClick = defaults.bool(forKey: Key.rehideOnOutsideClick)
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
        sectionOverrides = (defaults.dictionary(forKey: Key.sectionOverrides) as? [String: String]) ?? [:]
        lastPhysicalSections = (defaults.dictionary(forKey: Key.lastPhysicalSections) as? [String: String]) ?? [:]
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

    func lastPhysicalSection(for key: String) -> MenuSection? {
        guard let raw = lastPhysicalSections[key] else { return nil }
        return MenuSection(rawValue: raw)
    }

    func setLastPhysicalSection(_ section: MenuSection, for key: String) {
        guard lastPhysicalSections[key] != section.rawValue else { return }
        lastPhysicalSections[key] = section.rawValue
        defaults.set(lastPhysicalSections, forKey: Key.lastPhysicalSections)
    }

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
}
