import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var sections: SectionController!
    private var model: ItemsModel!
    private var settingsWindow: SettingsWindowController?
    private var didPromptForTrust = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarHider.shared.showAll()
        sections = SectionController()
        model = ItemsModel(controller: sections)
        sections.onOpenSettings = { [weak self] in self?.openSettings() }
        sections.tuckedItems = { [weak self] in self?.model.items.filter { $0.section != .visible } ?? [] }
        sections.onOpenItem = { [weak self] in self?.model.trigger($0) }
        sections.onWillCollapse = { [weak self] in
            self?.model.syncBeforeCollapse()
        }
        sections.onLayoutChanged = { [weak self] in
            guard let self else { return }
            self.model.checkTrust()
            if !self.model.isTrusted {
                // Layout shifts fire constantly (clock, other apps' icons); prompt once per launch, not per shift.
                guard !self.didPromptForTrust else { return }
                self.didPromptForTrust = true
                self.openSettings()
                self.model.requestTrust()
            } else {
                self.model.refresh(syncFromDividers: false)
            }
        }

        // Wait briefly for MenuBarAgent to materialize the status item scenes before scanning.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.model.refresh(syncFromDividers: false)
        }

        if !MenuBarHider.shared.isSupported {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "MenuTuck can't hide icons on this macOS version"
                alert.informativeText = "The menu bar API MenuTuck relies on is missing, probably after a macOS update. Icons will stay visible. Check for a newer MenuTuck release."
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }

        // Show the settings window once, so a new user sees how the app works.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didOnboard") {
            defaults.set(true, forKey: "didOnboard")
            openSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MenuBarHider.shared.showAll()
    }

    // Launching the app again from Finder / Spotlight opens the settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    private func openSettings() {
        if settingsWindow == nil {
            let controller = SettingsWindowController(sections: sections, model: model)
            controller.onClose = { [weak self] in self?.settingsWindow = nil }
            settingsWindow = controller
        }
        settingsWindow?.show()
    }
}
