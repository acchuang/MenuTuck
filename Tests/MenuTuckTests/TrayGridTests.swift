import XCTest
@testable import MenuTuck

final class TrayGridTests: XCTestCase {
    private func item(_ name: String, _ section: MenuSection, detail: String = "", pid: pid_t = 1) -> MenuBarItem {
        MenuBarItem(id: name, pid: pid, childIndex: 0, appName: name, bundleID: nil, detail: detail,
                    frame: .zero, isFromAX: true, section: section)
    }

    func testNotRunningAppsComeLast() {
        let items = [item("Off", .hidden, pid: 0), item("AH", .alwaysHidden), item("On", .hidden)]
        XCTAssertEqual(TrayGrid.tiles(from: items, query: "").map(\.appName), ["On", "AH", "Off"])
    }

    func testTilesListHiddenThenAlwaysHiddenAndFilter() {
        let items = [item("A", .alwaysHidden), item("B", .visible), item("C", .hidden), item("D", .hidden, detail: "Battery 80%")]
        XCTAssertEqual(TrayGrid.tiles(from: items, query: "").map(\.appName), ["C", "D", "A"])
        XCTAssertEqual(TrayGrid.tiles(from: items, query: "battery").map(\.appName), ["D"])
        XCTAssertEqual(TrayGrid.tiles(from: items, query: "b"), TrayGrid.tiles(from: items, query: "battery"), "visible items never show")
    }

    func testArrowsMoveInTheGridAndStopAtEdges() {
        XCTAssertEqual(TrayGrid.move(0, keyCode: 124, count: 7), 1)
        XCTAssertEqual(TrayGrid.move(0, keyCode: 123, count: 7), 0)
        XCTAssertEqual(TrayGrid.move(1, keyCode: 125, count: 7), 6)
        XCTAssertEqual(TrayGrid.move(2, keyCode: 125, count: 7), 2, "no tile below")
        XCTAssertEqual(TrayGrid.move(6, keyCode: 126, count: 7), 1)
    }
}
