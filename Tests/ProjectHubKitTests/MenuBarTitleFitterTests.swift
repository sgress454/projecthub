import XCTest
@testable import ProjectHubKit

final class MenuBarTitleFitterTests: XCTestCase {
    func testShowNameDisabledReturnsIconOnly() {
        XCTAssertEqual(
            MenuBarTitleFitter.progressiveForms(name: "api", showName: false),
            [.iconOnly]
        )
    }

    func testEmptyNameReturnsIconOnly() {
        XCTAssertEqual(
            MenuBarTitleFitter.progressiveForms(name: "", showName: true),
            [.iconOnly]
        )
    }

    func testShortNameProducesFullPlusIconOnly() {
        let forms = MenuBarTitleFitter.progressiveForms(name: "x", showName: true)
        XCTAssertEqual(forms, [.full(" x"), .iconOnly])
    }

    func testProgressionHalvesCharCount() {
        let forms = MenuBarTitleFitter.progressiveForms(
            name: "abcdefgh", // 8 chars
            showName: true
        )
        // Expected: full, 4…, 2…, 1…, iconOnly
        XCTAssertEqual(forms, [
            .full(" abcdefgh"),
            .truncated(" abcd\u{2026}"),
            .truncated(" ab\u{2026}"),
            .truncated(" a\u{2026}"),
            .iconOnly,
        ])
    }

    func testLongNameTerminatesWithIconOnly() {
        let name = String(repeating: "x", count: 40)
        let forms = MenuBarTitleFitter.progressiveForms(name: name, showName: true)
        XCTAssertEqual(forms.first, .full(" \(name)"))
        XCTAssertEqual(forms.last, .iconOnly)
        // Halving from 40 → 20, 10, 5, 2, 1 = 5 truncations, plus full + iconOnly = 7
        XCTAssertEqual(forms.count, 7)
    }

    func testNoDuplicateConsecutiveForms() {
        // A 3-char name: 3 → 1, so full, 1…, iconOnly — no repeats.
        let forms = MenuBarTitleFitter.progressiveForms(name: "abc", showName: true)
        XCTAssertEqual(forms, [
            .full(" abc"),
            .truncated(" a\u{2026}"),
            .iconOnly,
        ])
    }

    func testDisplayStringIsEmptyForIconOnly() {
        XCTAssertEqual(MenuBarTitleForm.iconOnly.displayString, "")
    }

    func testDisplayStringEchoesStoredString() {
        XCTAssertEqual(MenuBarTitleForm.full(" api").displayString, " api")
        XCTAssertEqual(MenuBarTitleForm.truncated(" pro\u{2026}").displayString, " pro\u{2026}")
    }
}
