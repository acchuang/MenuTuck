import AppKit
import Foundation
import os

@objc private protocol MBAssessmentModeConfigurationProtocol: NSObjectProtocol {
    init(allowedSystemItems: [NSNumber], allowedBundleIdentifiers: [String])
}

@objc private protocol MBAssessmentModeAssertionProtocol: NSObjectProtocol {
    init()
    func activate(withConfiguration config: AnyObject, completionHandler: @escaping (NSError?) -> Void)
    func invalidate()
}

/// Uses macOS's native `MenuBarClientCore` visibility restriction assertion (macOS 26+)
/// to hide and reveal menu bar icons in place based on MenuTuck's divider sections.
final class MenuBarHider {
    static let shared = MenuBarHider()

    private static let log = Logger(subsystem: "com.acchuang.MenuTuck", category: "MenuBarHider")

    private let configType: MBAssessmentModeConfigurationProtocol.Type?
    private let assertionType: MBAssessmentModeAssertionProtocol.Type?
    private var activeAssertion: MBAssessmentModeAssertionProtocol?

    /// Bundle identifiers currently hidden by the active assertion.
    private(set) var currentlyHiddenBundleIDs = Set<String>()
    private var currentlyAllowedBundleIDs = Set<String>()

    /// All `MBSystemItemIdentifier` raw values (0...15).
    private let allSystemItems: [NSNumber] = (0...15).map { NSNumber(value: $0) }

    var isSupported: Bool {
        configType != nil && assertionType != nil
    }

    private init() {
        _ = dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_NOW)
        // Private API: confirm every selector we call exists, so a changed signature
        // falls back to the spacer path instead of an unrecognized-selector crash.
        if let cfgClass = NSClassFromString("MBAssessmentModeConfiguration"),
           let assClass = NSClassFromString("MBAssessmentModeAssertion"),
           class_respondsToSelector(cfgClass, NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")),
           class_respondsToSelector(assClass, #selector(MBAssessmentModeAssertionProtocol.activate(withConfiguration:completionHandler:))),
           class_respondsToSelector(assClass, #selector(MBAssessmentModeAssertionProtocol.invalidate)) {
            configType = unsafeBitCast(cfgClass, to: MBAssessmentModeConfigurationProtocol.Type.self)
            assertionType = unsafeBitCast(assClass, to: MBAssessmentModeAssertionProtocol.Type.self)
        } else {
            configType = nil
            assertionType = nil
        }
    }

    /// Hides the given set of bundle identifiers from the menu bar while keeping all other running apps visible.
    func apply(hiddenBundleIDs: Set<String>) {
        guard let configType, let assertionType else { return }

        let cleanHidden = hiddenBundleIDs.subtracting([
            Bundle.main.bundleIdentifier ?? "com.acchuang.MenuTuck",
            "com.acchuang.MenuTuck",
            "MenuTuck",
            "com.apple.MenuBarAgent",
            "com.apple.controlcenter",
            "com.apple.systemuiserver",
            "com.apple.screencaptureui",
        ])

        guard !cleanHidden.isEmpty else {
            showAll()
            return
        }

        var allowedBundles = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )
        allowedBundles.insert(Bundle.main.bundleIdentifier ?? "com.acchuang.MenuTuck")
        allowedBundles.insert("com.acchuang.MenuTuck")
        allowedBundles.subtract(cleanHidden)

        if activeAssertion != nil,
           cleanHidden == currentlyHiddenBundleIDs,
           allowedBundles == currentlyAllowedBundleIDs {
            return
        }

        currentlyHiddenBundleIDs = cleanHidden
        currentlyAllowedBundleIDs = allowedBundles

        // System item 4 is `keyboard` (com.apple.TextInputMenuAgent).
        let allowedSys: [NSNumber]
        if cleanHidden.contains("com.apple.TextInputMenuAgent") {
            allowedSys = allSystemItems.filter { $0.intValue != 4 }
        } else {
            allowedSys = allSystemItems
        }

        let config = configType.init(
            allowedSystemItems: allowedSys,
            allowedBundleIdentifiers: Array(allowedBundles)
        )

        // Always invalidate the previous assertion before activating a new one so MenuBarAgent
        // does not keep an older VisibilityRestrictionXPCServer session alive.
        let previousAssertion = activeAssertion
        activeAssertion = nil
        previousAssertion?.invalidate()

        let newAssertion = assertionType.init()
        activeAssertion = newAssertion
        newAssertion.activate(withConfiguration: config) { error in
            if let error {
                Self.log.error("MBAssessmentModeAssertion activate failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Restores all hidden menu bar icons.
    func showAll() {
        currentlyHiddenBundleIDs.removeAll()
        currentlyAllowedBundleIDs.removeAll()
        let previousAssertion = activeAssertion
        activeAssertion = nil
        previousAssertion?.invalidate()
    }
}
