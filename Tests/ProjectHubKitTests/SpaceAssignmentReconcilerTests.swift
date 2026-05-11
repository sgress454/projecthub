import XCTest
@testable import ProjectHubKit

final class SpaceAssignmentReconcilerTests: XCTestCase {
    private func shape(_ pairs: [(Int, UInt64)]) -> SpaceShape {
        SpaceShape(entries: pairs.map { .init(position: $0.0, id64: $0.1) })
    }

    private func project(name: String, space: Int, id64: UInt64? = nil) -> Project {
        Project(name: name, space: space, spaceID64: id64)
    }

    // MARK: - Lazy capture

    func testLazyCapturePopulatesIDFromCurrentPosition() {
        let projects = [project(name: "alpha", space: 2)]
        let s = shape([(1, 100), (2, 200), (3, 300)])
        let updated = SpaceAssignmentReconciler.reconcile(projects: projects, shape: s)
        XCTAssertEqual(updated[0].spaceID64, 200)
        XCTAssertEqual(updated[0].space, 2)
    }

    func testLazyCaptureSkippedWhenPositionAbsent() {
        // User has Space=12 saved but only 4 actual Spaces exist.
        let projects = [project(name: "alpha", space: 12)]
        let s = shape([(1, 1), (2, 2), (3, 3), (4, 4)])
        let updated = SpaceAssignmentReconciler.reconcile(projects: projects, shape: s)
        XCTAssertNil(updated[0].spaceID64)
        XCTAssertEqual(updated[0].space, 12, "space preserved for later capture")
    }

    // MARK: - Renumber

    func testReorderUpdatesSpaceFromCachedID() {
        // Project was on Space 1 (id 100). User reorders so id 100 is now at position 3.
        let projects = [project(name: "alpha", space: 1, id64: 100)]
        let s = shape([(1, 999), (2, 998), (3, 100)])
        let updated = SpaceAssignmentReconciler.reconcile(projects: projects, shape: s)
        XCTAssertEqual(updated[0].space, 3)
        XCTAssertEqual(updated[0].spaceID64, 100)
    }

    func testInsertedSpaceShiftsHigherPositionsUp() {
        // Projects A,B,C on Spaces 1,2,3 with ids 10,20,30.
        // A new Space (id 25) gets inserted at position 3, pushing C from 3 to 4.
        let projects = [
            project(name: "A", space: 1, id64: 10),
            project(name: "B", space: 2, id64: 20),
            project(name: "C", space: 3, id64: 30),
        ]
        let s = shape([(1, 10), (2, 20), (3, 25), (4, 30)])
        let updated = SpaceAssignmentReconciler.reconcile(projects: projects, shape: s)
        XCTAssertEqual(updated[0].space, 1)
        XCTAssertEqual(updated[1].space, 2)
        XCTAssertEqual(updated[2].space, 4)
    }

    func testRemovedUnrelatedSpaceShiftsHigherPositionsDown() {
        // Projects A,B,C on positions 1,3,4 with ids 10,30,40.
        // Position 2 (id 20) gets removed; B and C shift down to 2 and 3.
        let projects = [
            project(name: "A", space: 1, id64: 10),
            project(name: "B", space: 3, id64: 30),
            project(name: "C", space: 4, id64: 40),
        ]
        let s = shape([(1, 10), (2, 30), (3, 40)])
        let updated = SpaceAssignmentReconciler.reconcile(projects: projects, shape: s)
        XCTAssertEqual(updated[0].space, 1)
        XCTAssertEqual(updated[1].space, 2)
        XCTAssertEqual(updated[2].space, 3)
    }

    func testRemovedProjectSpacePreservesLastKnownSpace() {
        // Project A's id (10) is gone from the shape.
        let projects = [project(name: "A", space: 4, id64: 10)]
        let s = shape([(1, 100), (2, 200)])
        let updated = SpaceAssignmentReconciler.reconcile(projects: projects, shape: s)
        XCTAssertEqual(updated[0].space, 4, "space preserved for restore convenience")
        XCTAssertEqual(updated[0].spaceID64, 10)
    }

    func testEmptyShapeReturnsInputUnchanged() {
        let projects = [
            project(name: "A", space: 1, id64: 10),
            project(name: "B", space: 2),
        ]
        let s = SpaceShape(entries: [])
        let updated = SpaceAssignmentReconciler.reconcile(projects: projects, shape: s)
        XCTAssertEqual(updated, projects)
    }

    // MARK: - unassignedIDs

    func testUnassignedIDsFlagsProjectsWithMissingCachedID() {
        let a = project(name: "A", space: 1, id64: 10) // present
        let b = project(name: "B", space: 2, id64: 99) // missing
        let c = project(name: "C", space: 3) // no cached id yet (lazy)
        let s = shape([(1, 10), (2, 200), (3, 300)])
        let unassigned = SpaceAssignmentReconciler.unassignedIDs(
            projects: [a, b, c], shape: s
        )
        XCTAssertEqual(unassigned, [b.id])
    }

    func testUnassignedIDsEmptyWhenShapeEmpty() {
        let a = project(name: "A", space: 1, id64: 10)
        let unassigned = SpaceAssignmentReconciler.unassignedIDs(
            projects: [a], shape: SpaceShape(entries: [])
        )
        XCTAssertTrue(unassigned.isEmpty)
    }
}
