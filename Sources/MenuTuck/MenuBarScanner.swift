import AppKit
import ApplicationServices

extension CGRect {
    /// True for frames materialized on the menu bar, not parked off-screen (e.g. y=1770).
    var isOnMenuBar: Bool { minY < 40 && minX > 5 }
}

/// One status item that belongs to another app.
struct MenuBarItem: Identifiable, Hashable {
    let id: String
    let pid: pid_t
    let childIndex: Int
    let appName: String
    let bundleID: String?
    let detail: String
    /// Global CG coordinates (top-left origin).
    let frame: CGRect
    let isFromAX: Bool
    var section: MenuSection = .visible

    var storageKey: String {
        bundleID ?? appName
    }
}

/// Discovers active menu bar items via `AXUIElement` (`kAXExtrasMenuBarAttribute`).
enum MenuBarScanner {
    /// Max wait per app for AX calls.
    private static let perAppTimeout: Float = 0.25

    /// Protected macOS menu bar hosts whose items are managed by Control Center.
    private static let excludedBundles: Set<String> = [
        "com.apple.MenuBarAgent",
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.screencaptureui",
    ]

    private static let excludedNames: Set<String> = [
        "swift-frontend",
        "MenuTuck",
        "GamePolicyAgent",
    ]

    /// Blocking. Call from a background queue.
    static func scan() -> [MenuBarItem] {
        guard AXIsProcessTrusted() else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier != ownPID else { return false }
            if let bid = app.bundleIdentifier, excludedBundles.contains(bid) { return false }
            let name = app.localizedName ?? app.executableURL?.lastPathComponent ?? ""
            if excludedNames.contains(name) { return false }
            return true
        }

        var results = [[MenuBarItem]](repeating: [], count: apps.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            let found = axItems(for: apps[index])
            lock.lock()
            results[index] = found
            lock.unlock()
        }

        var merged: [MenuBarItem] = []
        var seenBundles = Set<String>()

        for app in apps {
            let pid = app.processIdentifier
            let bid = app.bundleIdentifier
            let exe = app.executableURL?.lastPathComponent ?? ""
            if let bid, seenBundles.contains(bid) { continue }

            guard let axList = results.first(where: { $0.first?.pid == pid }), !axList.isEmpty else {
                continue
            }
            // Prefer on-screen items; pick the leftmost item for divider comparison.
            let onScreen = axList.filter { $0.frame.isOnMenuBar }
            let chosen = (onScreen.isEmpty ? axList : onScreen).min { $0.frame.minX < $1.frame.minX } ?? axList[0]
            let combinedDetail = axList.map(\.detail).first { !$0.isEmpty } ?? chosen.detail
            merged.append(
                MenuBarItem(
                    id: "\(bid ?? exe)-0",
                    pid: chosen.pid,
                    childIndex: chosen.childIndex,
                    appName: chosen.appName,
                    bundleID: bid,
                    detail: combinedDetail,
                    frame: chosen.frame,
                    isFromAX: true
                )
            )
            if let bid { seenBundles.insert(bid) }
        }

        return merged.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// Triggers a status item via Accessibility `AXPress`.
    @discardableResult
    static func press(_ item: MenuBarItem) -> Bool {
        let axApp = AXUIElementCreateApplication(item.pid)
        AXUIElementSetMessagingTimeout(axApp, perAppTimeout)
        guard let bar: AXUIElement = element(axApp, kAXExtrasMenuBarAttribute),
              let children: [AXUIElement] = array(bar, kAXChildrenAttribute),
              children.indices.contains(item.childIndex) else { return false }
        let target = children[item.childIndex]
        return AXUIElementPerformAction(target, kAXPressAction as CFString) == .success
    }

    private static func axItems(for app: NSRunningApplication) -> [MenuBarItem] {
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, perAppTimeout)

        guard let bar: AXUIElement = element(axApp, kAXExtrasMenuBarAttribute),
              let children: [AXUIElement] = array(bar, kAXChildrenAttribute) else { return [] }

        let appName = app.localizedName ?? app.bundleIdentifier ?? "PID \(pid)"
        let bid = app.bundleIdentifier
        return children.enumerated().compactMap { index, child in
            guard let origin = point(child, kAXPositionAttribute),
                  let size = size(child, kAXSizeAttribute),
                  size.width > 0 else { return nil }
            let detail = [string(child, kAXTitleAttribute), string(child, kAXDescriptionAttribute),
                          string(child, kAXHelpAttribute)]
                .compactMap { $0 }
                .first { !$0.isEmpty } ?? ""
            return MenuBarItem(
                id: "\(bid ?? "\(pid)")-\(index)",
                pid: pid,
                childIndex: index,
                appName: displayName(appName, bundleID: bid),
                bundleID: bid,
                detail: detail,
                frame: CGRect(origin: origin, size: size),
                isFromAX: true
            )
        }
    }

    private static func displayName(_ name: String, bundleID: String?) -> String {
        switch bundleID {
        case "com.apple.TextInputMenuAgent": return "Input Sources"
        case "com.apple.Passwords.MenuBarExtra": return "Passwords"
        default: return name
        }
    }

    // MARK: - AX helpers

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func array(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        copy(element, attribute) as? [AXUIElement]
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    private static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var result = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &result) ? result : nil
    }

    private static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var result = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &result) ? result : nil
    }
}
