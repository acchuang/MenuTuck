import XCTest
@testable import MenuTuck

final class UpdateCheckerTests: XCTestCase {
    func testNewerPatch() { XCTAssertTrue(UpdateChecker.isNewer("v0.1.6", than: "0.1.5")) }
    func testNumericNotLexical() { XCTAssertTrue(UpdateChecker.isNewer("v0.1.10", than: "0.1.9")) }
    func testSameIsNotNewer() { XCTAssertFalse(UpdateChecker.isNewer("v0.1.5", than: "0.1.5")) }
    func testOlderIsNotNewer() { XCTAssertFalse(UpdateChecker.isNewer("v0.1.4", than: "0.1.5")) }
}
