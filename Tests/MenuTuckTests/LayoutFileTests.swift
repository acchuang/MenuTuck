import XCTest
@testable import MenuTuck

final class LayoutFileTests: XCTestCase {
    func testParseKeepsKnownSectionsOnly() throws {
        let json = #"{"alwaysHiddenEnabled": true, "sections": {"a": "hidden", "b": "alwaysHidden", "c": "bogus"}}"#
        let layout = try Preferences.parseLayout(Data(json.utf8))
        XCTAssertEqual(layout, .init(sections: ["a": "hidden", "b": "alwaysHidden"], alwaysHiddenEnabled: true))
    }

    func testParseRejectsOtherJSON() {
        XCTAssertThrowsError(try Preferences.parseLayout(Data(#"{"foo": 1}"#.utf8)))
    }
}
