import Carbon.HIToolbox
import XCTest
@testable import MenuTuck

final class HotkeysTests: XCTestCase {
    func testBindRebindAndUnbind() {
        let mods = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        XCTAssertTrue(Hotkeys.set(99, keyCode: UInt32(kVK_F19), modifiers: mods))
        XCTAssertTrue(Hotkeys.set(99, keyCode: UInt32(kVK_F19), modifiers: mods), "same combo is a no-op")
        XCTAssertTrue(Hotkeys.set(99, keyCode: UInt32(kVK_F18), modifiers: mods), "rebinding releases the old combo")
        XCTAssertTrue(Hotkeys.set(98, keyCode: UInt32(kVK_F19), modifiers: mods), "the old combo is free again")
        XCTAssertTrue(Hotkeys.set(99, keyCode: nil))
        XCTAssertTrue(Hotkeys.set(98, keyCode: nil))
    }
}
