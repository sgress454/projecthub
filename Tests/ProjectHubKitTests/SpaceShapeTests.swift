import XCTest
@testable import ProjectHubKit

final class SpaceShapeTests: XCTestCase {
    func testParsesId64Key() {
        let displays: [[String: Any]] = [
            ["Spaces": [
                ["id64": NSNumber(value: UInt64(101))],
                ["id64": NSNumber(value: UInt64(102))],
            ]],
        ]
        let shape = SpaceShape.parse(displays: displays)
        XCTAssertEqual(shape.entries.count, 2)
        XCTAssertEqual(shape.id(at: 1), 101)
        XCTAssertEqual(shape.id(at: 2), 102)
        XCTAssertEqual(shape.position(of: 102), 2)
    }

    func testFallsBackToManagedSpaceIDKey() {
        let displays: [[String: Any]] = [
            ["Spaces": [
                ["ManagedSpaceID": NSNumber(value: UInt64(7))],
            ]],
        ]
        let shape = SpaceShape.parse(displays: displays)
        XCTAssertEqual(shape.id(at: 1), 7)
    }

    func testFlattensAcrossDisplays() {
        let displays: [[String: Any]] = [
            ["Spaces": [
                ["id64": NSNumber(value: UInt64(1))],
                ["id64": NSNumber(value: UInt64(2))],
            ]],
            ["Spaces": [
                ["id64": NSNumber(value: UInt64(3))],
            ]],
        ]
        let shape = SpaceShape.parse(displays: displays)
        XCTAssertEqual(shape.entries.count, 3)
        XCTAssertEqual(shape.id(at: 1), 1)
        XCTAssertEqual(shape.id(at: 2), 2)
        XCTAssertEqual(shape.id(at: 3), 3)
    }

    func testSkipsUnreadableSpacesButPreservesPositions() {
        let displays: [[String: Any]] = [
            ["Spaces": [
                ["id64": NSNumber(value: UInt64(1))],
                // Position 2 has neither key — it should be skipped from
                // entries, but Space at position 3 must keep its number.
                ["unrelated": "key"],
                ["id64": NSNumber(value: UInt64(3))],
            ]],
        ]
        let shape = SpaceShape.parse(displays: displays)
        XCTAssertEqual(shape.entries.count, 2)
        XCTAssertEqual(shape.id(at: 1), 1)
        XCTAssertNil(shape.id(at: 2))
        XCTAssertEqual(shape.id(at: 3), 3)
    }

    func testEmptyDisplaysProduceEmptyShape() {
        XCTAssertTrue(SpaceShape.parse(displays: []).isEmpty)
        XCTAssertTrue(SpaceShape.parse(displays: [["Spaces": []]]).isEmpty)
    }

    func testEqualityAndAccessors() {
        let a = SpaceShape(entries: [
            .init(position: 1, id64: 10),
            .init(position: 2, id64: 20),
        ])
        let b = SpaceShape(entries: [
            .init(position: 1, id64: 10),
            .init(position: 2, id64: 20),
        ])
        let c = SpaceShape(entries: [.init(position: 1, id64: 10)])
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertEqual(a.position(of: 20), 2)
        XCTAssertNil(a.position(of: 999))
    }
}
