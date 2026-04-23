import XCTest
@testable import ProjectHubKit

final class MissionControlShortcutsTests: XCTestCase {
    func testHotkeyIdMappingCovers1Through16() {
        XCTAssertEqual(MissionControlShortcuts.symbolicHotkeyId(forSpace: 1), 118)
        XCTAssertEqual(MissionControlShortcuts.symbolicHotkeyId(forSpace: 9), 126)
        XCTAssertEqual(MissionControlShortcuts.symbolicHotkeyId(forSpace: 10), 127)
        XCTAssertEqual(MissionControlShortcuts.symbolicHotkeyId(forSpace: 16), 133)
    }

    func testHotkeyIdIsNilOutsideSupportedRange() {
        XCTAssertNil(MissionControlShortcuts.symbolicHotkeyId(forSpace: 0))
        XCTAssertNil(MissionControlShortcuts.symbolicHotkeyId(forSpace: 17))
        XCTAssertNil(MissionControlShortcuts.symbolicHotkeyId(forSpace: -1))
    }

    func testReturnsTrueWhenEntryExistsAndEnabledIsTrue() {
        let dict: [String: Any] = [
            "126": ["enabled": true, "value": [:]],
        ]
        XCTAssertEqual(
            MissionControlShortcuts.isSwitchToDesktopEnabled(space: 9, reader: { dict }),
            true
        )
    }

    func testReturnsFalseWhenEntryExistsAndEnabledIsFalse() {
        let dict: [String: Any] = [
            "126": ["enabled": false, "value": [:]],
        ]
        XCTAssertEqual(
            MissionControlShortcuts.isSwitchToDesktopEnabled(space: 9, reader: { dict }),
            false
        )
    }

    func testReturnsFalseWhenEntryMissingFromPopulatedDict() {
        // Dict is readable but our ID isn't present — macOS treats this as
        // "not bound" for our purposes.
        let dict: [String: Any] = [
            "118": ["enabled": true, "value": [:]],
        ]
        XCTAssertEqual(
            MissionControlShortcuts.isSwitchToDesktopEnabled(space: 9, reader: { dict }),
            false
        )
    }

    func testReturnsNilWhenDomainIsUnreadable() {
        XCTAssertNil(
            MissionControlShortcuts.isSwitchToDesktopEnabled(space: 9, reader: { nil })
        )
    }

    func testReturnsNilForUnsupportedSpaceEvenWhenDomainReadable() {
        let dict: [String: Any] = ["126": ["enabled": true]]
        XCTAssertNil(
            MissionControlShortcuts.isSwitchToDesktopEnabled(space: 17, reader: { dict })
        )
    }
}
