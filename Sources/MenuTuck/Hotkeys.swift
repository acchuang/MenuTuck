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
