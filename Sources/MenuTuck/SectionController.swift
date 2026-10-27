import AppKit
import ApplicationServices
import Combine

/// A menu bar section, from the user's point of view.
enum MenuSection: String, CaseIterable, Identifiable {
    case visible, hidden, alwaysHidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visible: return "Visible"
        case .hidden: return "Hidden"
        case .alwaysHidden: return "Always Hidden"
        }
    }

    var symbol: String {
        switch self {
        case .visible: return "eye"
        case .hidden: return "eye.slash"
        case .alwaysHidden: return "lock"
        }
    }
}

enum BarState: String, CaseIterable, Identifiable {
    /// Hidden and always-hidden icons are off screen.
    case collapsed
    /// Hidden icons show. Always-hidden icons stay off screen.
    case expanded
    /// All icons show.
    case showAll

    var id: String { rawValue }

    var label: String {
        switch self {
        case .collapsed: return "Hidden"
        case .expanded: return "Expanded"
        case .showAll: return "Show All"
        }
    }
}

/// Positions of MenuTuck's own status items, in global CG coordinates (top-left origin).
struct DividerLayout {
    var toggle: CGRect
    var alwaysHidden: CGRect?
}

/// Owns the MenuTuck status items (`|‹` / `|›` and `‖`) and drives native icon hiding.
final class SectionController: NSObject, ObservableObject {
    static let collapsedLength: CGFloat = 10_000
    static let dividerLength: CGFloat = 14
    static let toggleLength: CGFloat = 24

    static let toggleID = "MenuTuckToggle"
    static let hiddenDividerID = "MenuTuckHiddenDivider"
    static let alwaysHiddenDividerID = "MenuTuckAlwaysHiddenDivider"

    let toggleItem: NSStatusItem
    let alwaysHiddenDivider: NSStatusItem

    private var alwaysHiddenConstraint: NSLayoutConstraint?

    @Published private(set) var state: BarState = .collapsed
    private var rehideTimer: Timer?
    private var dividerPollTimer: Timer?
    private var lastObservedToggleX: CGFloat?
    private var lastObservedAlwaysHiddenX: CGFloat?
    private var lastApplyTime: Date = .distantPast
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var outsideClickMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private let prefs = Preferences.shared
    private let hider = MenuBarHider.shared

    var onOpenSettings: (() -> Void)?
    var onLayoutChanged: (() -> Void)?
    var onWillCollapse: (() -> Void)?

    override init() {
        // Ensure AppKit does not restore a stale `Visible = 0` / `VisibleCC = 0` from UserDefaults.
        let defaults = UserDefaults.standard
        for id in [Self.toggleID, Self.alwaysHiddenDividerID] {
            defaults.set(true, forKey: "NSStatusItem Visible \(id)")
            defaults.set(true, forKey: "NSStatusItem VisibleCC \(id)")
        }

        // Two status items divide the menu bar into 3 unambiguous sections:
        // [Always Hidden]   ‖   [Hidden]   |›   [Visible]
        let bar = NSStatusBar.system
        toggleItem = bar.statusItem(withLength: Self.toggleLength)
        toggleItem.autosaveName = Self.toggleID
        toggleItem.isVisible = true
        alwaysHiddenDivider = bar.statusItem(withLength: Self.dividerLength)
        alwaysHiddenDivider.autosaveName = Self.alwaysHiddenDividerID
        alwaysHiddenDivider.isVisible = true
        super.init()

        alwaysHiddenConstraint = Self.findWidthConstraint(for: alwaysHiddenDivider)

        configureButtons()
        configureMonitors()
        startDividerPositionWatcher()
        prefs.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.apply() }
            }
            .store(in: &cancellables)

        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onLayoutChanged?()
        }
        wsCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onLayoutChanged?()
        }

        // Start with the dividers visible so MenuBarAgent materializes both scenes before the initial scan.
        alwaysHiddenDivider.button?.image = Self.alwaysHiddenDividerImage
        toggleItem.button?.image = Self.toggleImage(collapsed: true, showDivider: prefs.showDividers)
    }

    deinit {
        dividerPollTimer?.invalidate()
    }

    // MARK: - State

    func set(_ newState: BarState) {
        let wasExpanded = (state != .collapsed)
        state = newState
        if newState == .collapsed, wasExpanded {
            onWillCollapse?()
        }
        apply()
    }

    func toggle() {
        set(state == .collapsed ? .expanded : .collapsed)
    }

    func apply() {
        lastApplyTime = Date()
        let ahEnabled = prefs.alwaysHiddenEnabled
        let showDivs = prefs.showDividers

        if hider.isSupported {
            switch state {
            case .collapsed:
                setDivider(alwaysHiddenDivider, constraint: &alwaysHiddenConstraint, visible: false, image: Self.alwaysHiddenDividerImage)
                hider.apply(hiddenBundleIDs: prefs.bundleIDs(in: [.hidden, .alwaysHidden]))

            case .expanded:
                setDivider(alwaysHiddenDivider, constraint: &alwaysHiddenConstraint, visible: ahEnabled && showDivs, image: Self.alwaysHiddenDividerImage)
                let toHide: Set<MenuSection> = ahEnabled ? [.alwaysHidden] : []
                hider.apply(hiddenBundleIDs: prefs.bundleIDs(in: toHide))

            case .showAll:
                setDivider(alwaysHiddenDivider, constraint: &alwaysHiddenConstraint, visible: ahEnabled && showDivs, image: Self.alwaysHiddenDividerImage)
                hider.showAll()
            }
        } else {
            switch state {
            case .collapsed:
                alwaysHiddenDivider.length = Self.collapsedLength
                alwaysHiddenDivider.button?.image = nil

            case .expanded:
                alwaysHiddenDivider.length = ahEnabled ? Self.collapsedLength : 0
                alwaysHiddenDivider.button?.image = nil

            case .showAll:
                alwaysHiddenDivider.length = ahEnabled ? Self.dividerLength : 0
                alwaysHiddenDivider.button?.image = ahEnabled ? Self.alwaysHiddenDividerImage : nil
            }
        }

        toggleItem.button?.image = Self.toggleImage(
            collapsed: state == .collapsed,
            showDivider: showDivs
        )

        scheduleRehide()
    }

    /// Toggles a divider between `14 pt` visible and `0 pt` invisible without setting
    /// `isVisible = false` (which would cause `MenuBarAgent` to forget its position).
    private func setDivider(
        _ item: NSStatusItem,
        constraint: inout NSLayoutConstraint?,
        visible: Bool,
        image: NSImage
    ) {
        if constraint == nil {
            constraint = Self.findWidthConstraint(for: item)
        }
        if visible {
            constraint?.isActive = true
            item.length = Self.dividerLength
            item.button?.image = image
            item.button?.isEnabled = true
            item.button?.appearsDisabled = false
            item.button?.alphaValue = 1
        } else {
            constraint?.isActive = false
            item.length = 0
            item.button?.image = nil
            item.button?.isEnabled = false
            item.button?.appearsDisabled = true
            item.button?.alphaValue = 0
            if let win = item.button?.window {
                win.setContentSize(NSSize(width: 1, height: win.frame.height))
            }
        }
    }

    private static func findWidthConstraint(for item: NSStatusItem) -> NSLayoutConstraint? {
        guard let button = item.button,
              let contentView = button.window?.contentView else { return nil }
        return contentView.constraintsAffectingLayout(for: .horizontal)
            .first { $0.secondItem === button.superview }
    }

    private func scheduleRehide() {
        rehideTimer?.invalidate()
        rehideTimer = nil
        guard state != .collapsed, prefs.autoHide else { return }
        rehideTimer = Timer.scheduledTimer(withTimeInterval: prefs.autoHideDelay, repeats: false) { [weak self] _ in
            self?.set(.collapsed)
        }
    }

    // MARK: - Layout (for the item scanner / mover)

    /// Frames of MenuTuck's own items in global CG coordinates (top-left origin).
    /// Queries our own process via `AXUIElementCreateApplication(getpid())`, which works
    /// on macOS 27 without Accessibility permission and returns true `MenuBarAgent` frames.
    func layout() -> DividerLayout? {
        let axFrames = Self.ownAXFrames()
        let toggle = axFrames[Self.toggleID] ?? Self.globalFrame(of: toggleItem)
        guard let toggle, toggle.width > 0 else { return nil }

        let ah: CGRect?
        if prefs.alwaysHiddenEnabled {
            ah = axFrames[Self.alwaysHiddenDividerID] ?? Self.globalFrame(of: alwaysHiddenDivider)
        } else {
            ah = nil
        }
        return DividerLayout(toggle: toggle, alwaysHidden: ah)
    }

    private static func ownAXFrames() -> [String: CGRect] {
        var result: [String: CGRect] = [:]
        let axApp = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.2)
        var barRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXExtrasMenuBarAttribute as CFString, &barRef) == .success,
              let bar = barRef else { return result }
        var kidsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &kidsRef)
        for child in (kidsRef as? [AXUIElement]) ?? [] {
            var idRef: CFTypeRef?
            var descRef: CFTypeRef?
            var posRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXIdentifierAttribute as CFString, &idRef)
            AXUIElementCopyAttributeValue(child, kAXDescriptionAttribute as CFString, &descRef)
            AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &posRef)
            AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &sizeRef)
            guard let key = (idRef as? String) ?? (descRef as? String) else { continue }
            var pt = CGPoint.zero
            var sz = CGSize.zero
            if let posRef { AXValueGetValue(posRef as! AXValue, .cgPoint, &pt) }
            if let sizeRef { AXValueGetValue(sizeRef as! AXValue, .cgSize, &sz) }
            let frame = CGRect(origin: pt, size: sz)
            if frame.isOnMenuBar && sz.width > 0 {
                result[key] = frame
            }
        }
        return result
    }

    /// Fallback for older macOS where `NSStatusBarWindow.frame` has non-zero screen coordinates.
    private static func globalFrame(of item: NSStatusItem) -> CGRect? {
        guard let window = item.button?.window else { return nil }
        let f = window.frame
        guard f.minX > 5, f.height > 0 else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
    }

    // MARK: - Buttons and menu

    private func configureButtons() {
        for item in [toggleItem, alwaysHiddenDivider] {
            item.button?.target = self
            item.button?.action = #selector(statusItemClicked(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        toggleItem.button?.setAccessibilityIdentifier(Self.toggleID)
        toggleItem.button?.setAccessibilityLabel(Self.toggleID)
        toggleItem.button?.toolTip = "Click: show/hide icons · ⌥-click: show all · ⌘-drag icons left of |› to hide · Right-click: menu"

        alwaysHiddenDivider.button?.setAccessibilityIdentifier(Self.alwaysHiddenDividerID)
        alwaysHiddenDivider.button?.setAccessibilityLabel(Self.alwaysHiddenDividerID)
        alwaysHiddenDivider.button?.toolTip = "Always-Hidden section divider (‖). Click to show all · ⌘-drag icons to the left to always hide."
    }

    private func configureMonitors() {
        // ⌃⌥M (keyCode 46) toggles hidden icons.
        let isHotkey: (NSEvent) -> Bool = { [weak self] event in
            guard let self, self.prefs.enableGlobalHotkey else { return false }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            return event.keyCode == 46 && flags == [.control, .option]
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if isHotkey(event) {
                DispatchQueue.main.async { self?.toggle() }
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if isHotkey(event) {
                self?.toggle()
                return nil
            }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.prefs.rehideOnOutsideClick, self.state != .collapsed else { return }
            let mouse = NSEvent.mouseLocation
            // The screen under the click, not NSScreen.main (the key-window screen).
            let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            let screenMaxY = screen?.frame.maxY ?? 0
            // Collapse only when clicking below the menu bar. Its height varies (30 pt on an
            // external display, 38 pt on a notched one); 36 is the floor for auto-hide, where
            // visibleFrame reports no bar.
            let band = max(36, screen.map { $0.frame.maxY - $0.visibleFrame.maxY } ?? 0)
            if screenMaxY - mouse.y > band {
                DispatchQueue.main.async { self.set(.collapsed) }
            }
        }
    }

    /// Watches MenuTuck's own divider X coordinates via self-targeted `ownAXFrames()` (zero permissions).
    /// Because the macOS menu bar is right-aligned from Clock, any `⌘`-drag of an icon across `|›` or `‖`
    /// (or any `⌘`-drag of `|›` or `‖` itself) immediately shifts `toggle.minX` or `alwaysHidden.minX`.
    private func startDividerPositionWatcher() {
        dividerPollTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.checkIfDividerPositionsShifted()
        }
    }

    private func checkIfDividerPositionsShifted() {
        let frames = Self.ownAXFrames()
        guard let toggleFrame = frames[Self.toggleID], toggleFrame.width > 0 else { return }
        let ahX = frames[Self.alwaysHiddenDividerID]?.minX

        // While apply() is actively hiding/showing items, update baseline without triggering a re-scan.
        guard Date().timeIntervalSince(lastApplyTime) > 0.45 else {
            lastObservedToggleX = toggleFrame.minX
            lastObservedAlwaysHiddenX = ahX
            return
        }

        var shifted = false
        if let prevToggleX = lastObservedToggleX, abs(toggleFrame.minX - prevToggleX) > 1.5 {
            shifted = true
        }
        if state != .collapsed, let prevAHX = lastObservedAlwaysHiddenX, let ahX, abs(ahX - prevAHX) > 1.5 {
            shifted = true
        }

        lastObservedToggleX = toggleFrame.minX
        lastObservedAlwaysHiddenX = ahX

        if shifted {
            scheduleRehide()
            onLayoutChanged?()
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else if event?.modifierFlags.contains(.option) == true {
            set(state == .showAll ? .collapsed : .showAll)
        } else if sender === alwaysHiddenDivider.button {
            set(state == .showAll ? .expanded : .showAll)
        } else {
            toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let toggleTitle = state == .collapsed ? "Show Hidden Icons" : "Hide Icons"
        menu.addItem(withTitle: toggleTitle, action: #selector(menuToggle), keyEquivalent: "").target = self
        let showAll = menu.addItem(withTitle: "Show All Icons", action: #selector(menuShowAll), keyEquivalent: "")
        showAll.target = self
        showAll.isEnabled = state != .showAll
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MenuTuck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        toggleItem.menu = menu
        toggleItem.button?.performClick(nil)
        toggleItem.menu = nil
    }

    @objc private func menuToggle() { toggle() }
    @objc private func menuShowAll() { set(.showAll) }
    @objc private func menuSettings() { onOpenSettings?() }

    // MARK: - Images

    /// Combined divider bar + chevron (`|‹` when collapsed, `|›` when expanded) for the Hidden section boundary.
    private static func toggleImage(collapsed: Bool, showDivider: Bool) -> NSImage {
        let symbolName = collapsed ? "chevron.left" : "chevron.right"
        let chevron = NSImage(systemSymbolName: symbolName, accessibilityDescription: "MenuTuck")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        guard showDivider else {
            chevron?.isTemplate = true
            return chevron ?? NSImage()
        }
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            let bar = NSRect(x: 1.5, y: 2, width: 1.5, height: rect.height - 4)
            NSBezierPath(roundedRect: bar, xRadius: 0.75, yRadius: 0.75).fill()
            if let chevron {
                let cSize = chevron.size
                let dst = NSRect(
                    x: 5.5 + max(0, (10 - cSize.width) / 2),
                    y: (rect.height - cSize.height) / 2,
                    width: cSize.width,
                    height: cSize.height
                )
                chevron.draw(in: dst)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Double vertical bar `‖` for the Always-Hidden section divider.
    private static let alwaysHiddenDividerImage: NSImage = {
        let image = NSImage(size: NSSize(width: 8, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            let leftBar = NSRect(x: rect.midX - 2.25, y: 2, width: 1.5, height: rect.height - 4)
            let rightBar = NSRect(x: rect.midX + 0.75, y: 2, width: 1.5, height: rect.height - 4)
            NSBezierPath(roundedRect: leftBar, xRadius: 0.75, yRadius: 0.75).fill()
            NSBezierPath(roundedRect: rightBar, xRadius: 0.75, yRadius: 0.75).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
