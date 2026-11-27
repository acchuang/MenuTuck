import XCTest
@testable import MenuTuck

final class NewAssignmentTests: XCTestCase {
    private func assign(
        _ detected: MenuSection, saved: MenuSection? = nil, last: MenuSection? = nil,
        new: MenuSection? = nil, force: Bool = false
    ) -> MenuSection? {
        ItemsModel.newAssignment(detected: detected, saved: saved, lastPhysical: last, newAppSection: new, force: force)
    }

    func testNewAppFollowsThePreferenceElseItsPosition() {
        XCTAssertEqual(assign(.hidden), .hidden)
        XCTAssertEqual(assign(.visible), .visible)
        XCTAssertEqual(assign(.hidden, new: .visible), .visible)
        XCTAssertEqual(assign(.visible, new: .hidden), .hidden)
    }

    func testKnownAppIgnoresThePreference() {
        XCTAssertNil(assign(.visible, saved: .hidden, last: .visible, new: .visible))
        XCTAssertNil(assign(.visible, saved: .hidden, new: .visible), "assigned in Settings before it was ever seen")
    }

    func testCrossingADividerReassigns() {
        XCTAssertEqual(assign(.hidden, saved: .visible, last: .visible, new: .visible), .hidden)
    }

    func testFirstSightingAfterLaunchKeepsTheSavedSection() {
        XCTAssertNil(assign(.visible, saved: .alwaysHidden), "dividers re-placed on relaunch, not a drag")
        XCTAssertNil(assign(.hidden, saved: .visible))
    }

    func testFullSyncAlwaysFollowsPosition() {
        XCTAssertEqual(assign(.visible, saved: .hidden, last: .visible, new: .hidden, force: true), .visible)
    }

    func testSectionFromFramePreservesAlwaysHiddenWhenDividerCollapsed() {
        let toggle = CGRect(x: 900, y: 0, width: 24, height: 24)
        let layoutNoAH = DividerLayout(toggle: toggle, alwaysHidden: nil)
        let leftItem = CGRect(x: 700, y: 0, width: 20, height: 24)
        let rightItem = CGRect(x: 950, y: 0, width: 20, height: 24)

        XCTAssertEqual(
            ItemsModel.sectionFromFrame(leftItem, layout: layoutNoAH, alwaysHiddenEnabled: true, preserveAlwaysHidden: true),
            .alwaysHidden
        )
        XCTAssertEqual(
            ItemsModel.sectionFromFrame(leftItem, layout: layoutNoAH, alwaysHiddenEnabled: true, preserveAlwaysHidden: false),
            .hidden
        )
        XCTAssertEqual(
            ItemsModel.sectionFromFrame(rightItem, layout: layoutNoAH, alwaysHiddenEnabled: true, preserveAlwaysHidden: true),
            .visible
        )
    }

    func testSectionFromFrameUsesAlwaysHiddenDividerWhenExpanded() {
        let ah = CGRect(x: 800, y: 0, width: 14, height: 24)
        let toggle = CGRect(x: 900, y: 0, width: 24, height: 24)
        let layout = DividerLayout(toggle: toggle, alwaysHidden: ah)

        XCTAssertEqual(ItemsModel.sectionFromFrame(CGRect(x: 750, y: 0, width: 20, height: 24), layout: layout, alwaysHiddenEnabled: true), .alwaysHidden)
        XCTAssertEqual(ItemsModel.sectionFromFrame(CGRect(x: 850, y: 0, width: 20, height: 24), layout: layout, alwaysHiddenEnabled: true), .hidden)
        XCTAssertEqual(ItemsModel.sectionFromFrame(CGRect(x: 950, y: 0, width: 20, height: 24), layout: layout, alwaysHiddenEnabled: true), .visible)
    }
}
