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

    func testPollIntervalFastOnlyAroundCommand() {
        let p = DividerPollPolicy.self
        XCTAssertEqual(p.interval(commandHeld: true, secondsSinceRelease: 99, trusted: true), p.fast)
        XCTAssertEqual(p.interval(commandHeld: false, secondsSinceRelease: 0.5, trusted: true), p.fast)
        XCTAssertEqual(p.interval(commandHeld: false, secondsSinceRelease: 2, trusted: true), p.heartbeat)
        XCTAssertEqual(p.interval(commandHeld: true, secondsSinceRelease: 0, trusted: false), p.heartbeat)
    }

    func testBarStateLabelsDoNotCollideWithSectionTitles() {
        let stateLabels = Set(BarState.allCases.map(\.label))
        let sectionTitles = Set(MenuSection.allCases.map(\.title))
        XCTAssertTrue(stateLabels.isDisjoint(with: sectionTitles))
        XCTAssertEqual(BarState.collapsed.label, "Collapsed")
    }
}
