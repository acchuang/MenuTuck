import AppKit
import SwiftUI

/// Hosts the SwiftUI settings in an AppKit window.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let sections: SectionController
    private let model: ItemsModel

    init(sections: SectionController, model: ItemsModel) {
        self.sections = sections
        self.model = model
        let host = NSHostingController(rootView: SettingsView(prefs: .shared, sections: sections, model: model))
        let window = NSWindow(contentViewController: host)
        window.title = "MenuTuck"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 580, height: 560))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [model] in model.refresh() }
    }
}
