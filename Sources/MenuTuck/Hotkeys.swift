import AppKit
import Carbon.HIToolbox

/// System-wide shortcuts through Carbon hot keys. Unlike a global `NSEvent` monitor, the key press is
/// consumed (it never reaches the front app) and no Accessibility permission is needed.
/// Main thread only: Carbon delivers hot key events on the main run loop.
enum Hotkeys {
    private struct Entry {
        let keyCode: UInt32
        let modifiers: UInt32
        let ref: EventHotKeyRef
        let action: () -> Void
    }

    private static var entries: [UInt32: Entry] = [:]
    private static var handlerInstalled = false
    private static let signature: OSType = 0x4D54_636B // "MTck"

    /// Binds `id` to a key combo (Carbon modifier mask), replacing its previous combo. `keyCode: nil` unbinds it.
    /// Returns false when the system refuses the combo, e.g. another app already holds it.
    @discardableResult
    static func set(_ id: UInt32, keyCode: UInt32?, modifiers: UInt32 = 0, action: @escaping () -> Void = {}) -> Bool {
        if let old = entries[id] {
            if old.keyCode == keyCode, old.modifiers == modifiers { return true }
            UnregisterEventHotKey(old.ref)
            entries[id] = nil
        }
        guard let keyCode else { return true }
        installHandler()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, EventHotKeyID(signature: signature, id: id), GetEventDispatcherTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return false }
        entries[id] = Entry(keyCode: keyCode, modifiers: modifiers, ref: ref, action: action)
        return true
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var pressed = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed
            )
            guard status == noErr, pressed.signature == Hotkeys.signature else { return OSStatus(eventNotHandledErr) }
            Hotkeys.entries[pressed.id]?.action()
            return noErr
        }, 1, &spec, nil, nil)
    }
}

/// A recorded key combo. `modifiers` is a Carbon mask; `key` is the name shown in Settings.
struct Shortcut: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var key: String

    static let defaultToggle = Shortcut(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | optionKey), key: "M")

    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// "⌃⌥M", modifiers in the order macOS menus draw them.
    var label: String {
        let symbols = [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
        return symbols.filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + key
    }

    var plist: [String: Any] { ["keyCode": Int(keyCode), "modifiers": Int(modifiers), "key": key] }
}

extension Shortcut {
    init?(plist: [String: Any]) {
        guard let keyCode = plist["keyCode"] as? Int, let modifiers = plist["modifiers"] as? Int,
              let key = plist["key"] as? String, !key.isEmpty else { return nil }
        self.init(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers), key: key)
    }

    /// Nil unless ⌃, ⌥ or ⌘ is held: a bare or Shift-only key would swallow ordinary typing system-wide.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers = 0
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        if flags.contains(.command) { modifiers |= cmdKey }
        guard modifiers & (controlKey | optionKey | cmdKey) != 0 else { return nil }
        let typed = event.charactersIgnoringModifiers?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Keys with no printable name (Home, Page Up, …) report private-use characters; refuse them.
        guard let key = Self.namedKeys[Int(event.keyCode)] ?? typed, let first = key.unicodeScalars.first,
              !(0xF700...0xF8FF).contains(first.value) else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: UInt32(modifiers), key: key)
    }
}
