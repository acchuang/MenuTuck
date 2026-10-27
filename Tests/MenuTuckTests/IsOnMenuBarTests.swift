import XCTest
@testable import MenuTuck

final class IsOnMenuBarTests: XCTestCase {
    private func frame(_ x: CGFloat, _ y: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: 26, height: 24)
    }

    func testPrimaryDisplayItemIsOnBar() {
        XCTAssertTrue(frame(2839, 3.5).isOnMenuBar)
    }

    func testLeftDisplayNegativeXIsOnBar() {
        XCTAssertTrue(frame(-698, 7.5).isOnMenuBar)
    }

    func testParkedOffscreenIsNotOnBar() {
        XCTAssertFalse(frame(2839, 1770).isOnMenuBar)
    }

    func testUnplacedAtOriginIsNotOnBar() {
        XCTAssertFalse(frame(0, 0).isOnMenuBar)
    }
}
