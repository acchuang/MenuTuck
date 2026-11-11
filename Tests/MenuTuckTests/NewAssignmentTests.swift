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
        XCTAssertEqual(assign(.hidden, saved: .visible), .hidden, "first sighting outside Visible counts as a move")
    }

    func testFullSyncAlwaysFollowsPosition() {
        XCTAssertEqual(assign(.visible, saved: .hidden, last: .visible, new: .hidden, force: true), .visible)
    }
}
