import Foundation
import XCTest
@testable import ProjectHubKit

final class TerminalLauncherTests: XCTestCase {
    private var originalResolver: ((String) -> URL?)!

    override func setUp() {
        super.setUp()
        originalResolver = TerminalLauncher.resolveAppURL
    }

    override func tearDown() {
        TerminalLauncher.resolveAppURL = originalResolver
        super.tearDown()
    }

    func testIsAvailableTrueWhenResolverReturnsURL() {
        TerminalLauncher.resolveAppURL = { _ in URL(fileURLWithPath: "/Applications/iTerm.app") }
        XCTAssertTrue(TerminalLauncher.isAvailable(.iterm2))
        XCTAssertTrue(TerminalLauncher.isAvailable(.terminal))
    }

    func testIsAvailableFalseWhenResolverReturnsNil() {
        TerminalLauncher.resolveAppURL = { _ in nil }
        XCTAssertFalse(TerminalLauncher.isAvailable(.iterm2))
        XCTAssertFalse(TerminalLauncher.isAvailable(.terminal))
    }

    func testResolverIsPassedTheRightBundleId() {
        var seenBundleIds: [String] = []
        TerminalLauncher.resolveAppURL = { bundleId in
            seenBundleIds.append(bundleId)
            return nil
        }
        _ = TerminalLauncher.isAvailable(.iterm2)
        _ = TerminalLauncher.isAvailable(.terminal)
        XCTAssertEqual(seenBundleIds, ["com.googlecode.iterm2", "com.apple.Terminal"])
    }

    func testOpenReturnsFalseWhenAppNotInstalled() {
        TerminalLauncher.resolveAppURL = { _ in nil }
        let ok = TerminalLauncher.open(
            directoryURL: URL(fileURLWithPath: "/tmp"),
            using: .iterm2
        )
        XCTAssertFalse(ok)
    }
}
