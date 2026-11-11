import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine

/// Owns the MenuTuck status items (`|‹` / `|›` and `‖`) and drives native icon hiding.
final class SectionController: NSObject, ObservableObject {
    static let dividerLength: CGFloat = 14
    static let toggleLength: CGFloat = 24

    static let toggleID = "MenuTuckToggle"
    static let alwaysHiddenDividerID = "MenuTuckAlwaysHiddenDivider"

    let toggleItem: NSStatusItem
    let alwaysHiddenDivider: NSStatusItem

    private var alwaysHiddenConstraint: NSLayoutConstraint?

    static let toggleHotkeyID: UInt32 = 0
    static let showAllHotkeyID: UInt32 = 1

    @Published private(set) var state: BarState = .collapsed
    /// Hot key IDs the system refused to register, usually because another app holds the combo.
    @Published private(set) var refusedHotkeys: Set<UInt32> = []
    private var rehideTimer: Timer?
    private var dividerPollTimer: Timer?
    private var lastObservedToggleX: CGFloat?
    private var lastObservedAlwaysHiddenX: CGFloat?
    private var lastApplyTime: Date = .distantPast
    private var commandHeld = false
    private var commandReleasedAt: Date = .distantPast
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var outsideClickMonitor: Any?
    private var hoverMonitor: Any?
    private var hoverTimer: Timer?
    private var hoverFrame: CGRect?
    private var hoverFrameAt: Date = .distantPast
    /// The current reveal came from hovering and nothing was clicked since, so it ends when the pointer leaves the bar.
    private var revealedByHover = false
    private var cancellables = Set<AnyCancellable>()
    private let prefs = Preferences.shared
    private let hider = MenuBarHider.shared

    var onOpenSettings: (() -> Void)?
    var onLayoutChanged: (() -> Void)?
    var onWillCollapse: (() -> Void)?
    /// Items outside the Visible section, left to right, for the right-click menu.
    var tuckedItems: (() -> [MenuBarItem])?
    var onOpenItem: ((MenuBarItem) -> Void)?

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
        syncHoverMonitor()
        syncHotkeys()
        prefs.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.apply()
                    self?.syncHoverMonitor()
                    self?.syncHotkeys()
                }
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
        revealedByHover = false
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
            guard let self else { return }
            // Don't pull icons out from under the pointer or while Settings is in use; wait another round.
            if Self.pointerIsInMenuBar() || NSApp.keyWindow != nil {
                self.scheduleRehide()
            } else {
                self.set(.collapsed)
            }
        }
    }

    /// The bar's height varies (30 pt on an external display, 38 pt on a notched one); 36 is the
    /// floor for an auto-hiding bar, where `visibleFrame` reports none.
    private static func pointerIsInMenuBar() -> Bool {
        let mouse = NSEvent.mouseLocation
        // The screen under the pointer, not NSScreen.main (the key-window screen).
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return true }
        return screen.frame.maxY - mouse.y <= max(36, screen.frame.maxY - screen.visibleFrame.maxY)
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
        guard abs(f.minX) > 5, f.height > 0 else { return nil }
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
        toggleItem.button?.setAccessibilityLabel("MenuTuck, show or hide menu bar icons")
        toggleItem.button?.toolTip = "Click: show/hide icons · ⌥-click: show all · ⌘-drag icons left of |› to hide · Right-click: menu"

        alwaysHiddenDivider.button?.setAccessibilityIdentifier(Self.alwaysHiddenDividerID)
        alwaysHiddenDivider.button?.setAccessibilityLabel("MenuTuck, Always Hidden divider")
        alwaysHiddenDivider.button?.toolTip = "Always-Hidden section divider (‖). Click to show all · ⌘-drag icons to the left to always hide."
    }

    private func configureMonitors() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            // A click may have opened a hidden icon's menu; collapsing on pointer exit would close it.
            self.revealedByHover = false
            guard self.prefs.rehideOnOutsideClick, self.state != .collapsed else { return }
            if !Self.pointerIsInMenuBar() {
                DispatchQueue.main.async { self.set(.collapsed) }
            }
        }
    }

    private func syncHotkeys() {
        var refused = Set<UInt32>()
        func bind(_ id: UInt32, _ shortcut: Shortcut?, _ action: @escaping () -> Void) {
            if !Hotkeys.set(id, keyCode: shortcut?.keyCode, modifiers: shortcut?.modifiers ?? 0, action: action) {
                refused.insert(id)
            }
        }
        bind(Self.toggleHotkeyID, prefs.toggleShortcut) { [weak self] in self?.toggle() }
        bind(Self.showAllHotkeyID, prefs.showAllShortcut) { [weak self] in self?.toggleShowAll() }
        if refused != refusedHotkeys { refusedHotkeys = refused }
    }

    private func toggleShowAll() {
        set(state == .showAll ? .collapsed : .showAll)
    }

    /// Installs the global mouse monitor only while "reveal on hover" is on, so it costs nothing otherwise.
    /// The pointer is hit-tested against the toggle's AX frame: on macOS 27 the status item's own
    /// window frame is useless (see `layout()`), so a tracking area on the button cannot be trusted.
    private func syncHoverMonitor() {
        if prefs.hoverReveal, hoverMonitor == nil {
            hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
                self?.handleMouseMoved()
            }
        } else if !prefs.hoverReveal, let monitor = hoverMonitor {
            NSEvent.removeMonitor(monitor)
            hoverMonitor = nil
            hoverTimer?.invalidate()
            hoverTimer = nil
        }
    }

    private func handleMouseMoved() {
        guard state == .collapsed else {
            cancelHover()
            if revealedByHover, !Self.pointerIsInMenuBar() { set(.collapsed) }
            return
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x, y: primaryHeight - mouse.y)
        // Cheap reject first: this runs for every mouse move on screen.
        guard point.y < 60 else { return cancelHover() }

        if Date().timeIntervalSince(hoverFrameAt) > 1 {
            hoverFrame = Self.ownAXFrames()[Self.toggleID]
            hoverFrameAt = Date()
        }
        guard let frame = hoverFrame, frame.insetBy(dx: -2, dy: 0).contains(point) else { return cancelHover() }
        guard hoverTimer == nil else { return }
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.hoverTimer = nil
            guard self.state == .collapsed else { return }
            self.set(.expanded)
            self.revealedByHover = true
        }
    }

    private func cancelHover() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    /// Watches MenuTuck's own divider X coordinates via self-targeted `ownAXFrames()` (zero permissions).
    /// Because the macOS menu bar is right-aligned from Clock, any `⌘`-drag of an icon across `|›` or `‖`
    /// (or any `⌘`-drag of `|›` or `‖` itself) immediately shifts `toggle.minX` or `alwaysHidden.minX`.
    /// Polls every 0.35 s while `⌘` is down (plus a 1 s tail), else a 5 s heartbeat; see `DividerPollPolicy`.
    private func startDividerPositionWatcher() {
        let onFlags: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            let held = event.modifierFlags.contains(.command)
            guard held != self.commandHeld else { return }
            self.commandHeld = held
            if !held { self.commandReleasedAt = Date() }
            self.scheduleDividerPoll()
        }
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: onFlags)
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            onFlags(event)
            return event
        }
        scheduleDividerPoll()
    }

    private func scheduleDividerPoll() {
        dividerPollTimer?.invalidate()
        let interval = DividerPollPolicy.interval(
            commandHeld: commandHeld,
            secondsSinceRelease: Date().timeIntervalSince(commandReleasedAt),
            trusted: AXIsProcessTrusted()
        )
        dividerPollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.checkIfDividerPositionsShifted()
            self?.scheduleDividerPoll()
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
            toggleShowAll()
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
        // Lists tucked icons by name so one stays reachable even when the notch leaves no room to show it.
        let tucked = tuckedItems?() ?? []
        if !tucked.isEmpty {
            menu.addItem(.sectionHeader(title: "Hidden Icons"))
            let names = tucked.map(\.appName)
            for item in tucked {
                let shared = names.filter { $0 == item.appName }.count > 1 && !item.detail.isEmpty
                let entry = menu.addItem(
                    withTitle: shared ? "\(item.appName) — \(item.detail)" : item.appName,
                    action: #selector(menuOpenItem(_:)), keyEquivalent: ""
                )
                entry.target = self
                entry.representedObject = item
                let icon = item.appIcon.copy() as! NSImage
                icon.size = NSSize(width: 16, height: 16)
                entry.image = icon
            }
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Settings…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Check for Updates…", action: #selector(menuCheckUpdates), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MenuTuck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        toggleItem.menu = menu
        toggleItem.button?.performClick(nil)
        toggleItem.menu = nil
    }

    @objc private func menuToggle() { toggle() }
    @objc private func menuShowAll() { set(.showAll) }
    @objc private func menuOpenItem(_ sender: NSMenuItem) {
        if let item = sender.representedObject as? MenuBarItem { onOpenItem?(item) }
    }
    @objc private func menuSettings() { onOpenSettings?() }
    @objc private func menuCheckUpdates() { UpdateChecker.run() }
}
