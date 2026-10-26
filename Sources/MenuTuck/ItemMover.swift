import CoreGraphics
import Foundation

/// Moves a status item the same way a user does: a ⌘-drag in the menu bar.
/// Posting synthetic events needs the Accessibility permission.
enum ItemMover {
    private static let commandKeyCode: CGKeyCode = 55

    /// Blocking (about 1.1 s). Call from a background queue.
    static func drag(from start: CGPoint, to end: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        let restore = CGEvent(source: nil)?.location ?? start

        func postMouse(_ type: CGEventType, _ point: CGPoint, _ flags: CGEventFlags) {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                      mouseCursorPosition: point, mouseButton: .left) else { return }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }

        func postCommandKey(down: Bool) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: commandKeyCode, keyDown: down) else {
                return
            }
            event.flags = down ? .maskCommand : []
            event.post(tap: .cghidEventTap)
        }

        postMouse(.mouseMoved, start, [])
        usleep(100_000)
        postCommandKey(down: true)
        usleep(100_000)
        postMouse(.leftMouseDown, start, .maskCommand)
        usleep(250_000)

        // Small steps, so the menu bar re-orders items live as the cursor passes them.
        let steps = 30
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            postMouse(.leftMouseDragged, point, .maskCommand)
            usleep(20_000)
        }

        usleep(200_000)
        postMouse(.leftMouseUp, end, .maskCommand)
        usleep(100_000)
        postCommandKey(down: false)
        postMouse(.mouseMoved, restore, [])
    }
}
