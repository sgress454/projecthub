import Foundation
import XCTest
@testable import ProjectHubKit

final class HookInstallerTests: XCTestCase {
    private var tempDir: URL!
    private var settingsURL: URL!
    private var hookScriptURL: URL!
    private var installer: HookInstaller!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ProjectHubHookTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        settingsURL = tempDir.appendingPathComponent("claude-settings.json")
        hookScriptURL = tempDir.appendingPathComponent("hooks/projecthub-event.sh")
        installer = HookInstaller(
            settingsURL: settingsURL,
            hookScriptURL: hookScriptURL
        )
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func readSettings() throws -> [String: Any] {
        let data = try Data(contentsOf: settingsURL)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    // MARK: - Install into empty

    func testInstallIntoMissingSettingsCreatesFile() throws {
        try installer.install()

        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsURL.path))
        let settings = try readSettings()
        let hooks = settings["hooks"] as! [String: Any]
        for event in HookInstaller.hookEvents {
            XCTAssertNotNil(hooks[event], "missing hook for \(event)")
            let groups = hooks[event] as! [[String: Any]]
            XCTAssertEqual(groups.count, 1)
            let entries = groups[0]["hooks"] as! [[String: Any]]
            XCTAssertEqual(entries.count, 1)
            let cmd = entries[0]["command"] as! String
            XCTAssertTrue(cmd.contains(HookInstaller.marker))
            XCTAssertTrue(cmd.contains(hookScriptURL.path))
        }
    }

    func testInstallWritesHookScriptFileWithExecPermission() throws {
        try installer.install()
        XCTAssertTrue(FileManager.default.fileExists(atPath: hookScriptURL.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: hookScriptURL.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.int16Value ?? 0
        XCTAssertEqual(perms & 0o777, 0o755, "script must be executable")
        let content = try String(contentsOf: hookScriptURL)
        XCTAssertTrue(content.contains("exec >/dev/null 2>&1"))
        XCTAssertTrue(content.contains("events.jsonl"))
    }

    // MARK: - Install preserves user hooks

    func testInstallPreservesExistingUserHooks() throws {
        let userHooks: [String: Any] = [
            "hooks": [
                "Stop": [
                    [
                        "matcher": "",
                        "hooks": [
                            ["type": "command", "command": "echo 'user hook'"],
                        ],
                    ],
                ],
                "SessionStart": [
                    [
                        "matcher": "",
                        "hooks": [
                            ["type": "command", "command": "echo 'user session-start'"],
                        ],
                    ],
                ],
            ],
            "theme": "dark",
        ]
        try JSONSerialization.data(withJSONObject: userHooks, options: [])
            .write(to: settingsURL)

        try installer.install()

        let settings = try readSettings()
        XCTAssertEqual(settings["theme"] as? String, "dark", "top-level user field preserved")
        let hooks = settings["hooks"] as! [String: Any]
        let sessionStart = hooks["SessionStart"] as! [[String: Any]]
        XCTAssertEqual(sessionStart.count, 1, "non-projecthub event preserved")
        let stop = hooks["Stop"] as! [[String: Any]]
        XCTAssertEqual(stop.count, 2, "user Stop hook + projecthub Stop hook both present")
        let userStop = stop.first { group in
            let entries = group["hooks"] as! [[String: Any]]
            return (entries[0]["command"] as! String) == "echo 'user hook'"
        }
        XCTAssertNotNil(userStop, "user's Stop hook preserved verbatim")
    }

    // MARK: - Uninstall round-trips

    func testInstallThenUninstallProducesOriginalFile() throws {
        let original: [String: Any] = [
            "hooks": [
                "Stop": [
                    [
                        "matcher": "",
                        "hooks": [
                            ["type": "command", "command": "echo 'user'"],
                        ],
                    ],
                ],
            ],
            "misc": "preserved",
        ]
        let originalData = try JSONSerialization.data(
            withJSONObject: original, options: [.prettyPrinted, .sortedKeys]
        )
        try originalData.write(to: settingsURL)

        try installer.install()
        try installer.uninstall()

        let afterData = try Data(contentsOf: settingsURL)
        // Compare semantically, not byte-for-byte — both should deserialize equal.
        let afterObj = try JSONSerialization.jsonObject(with: afterData) as! [String: Any]
        let expectedObj = try JSONSerialization.jsonObject(with: originalData) as! [String: Any]
        XCTAssertEqual(afterObj["misc"] as? String, "preserved")
        let expectedHooks = expectedObj["hooks"] as! [String: Any]
        let afterHooks = afterObj["hooks"] as! [String: Any]
        XCTAssertEqual(
            (expectedHooks["Stop"] as! [[String: Any]]).count,
            (afterHooks["Stop"] as! [[String: Any]]).count
        )
        // No remnants of our marker.
        let asText = String(data: afterData, encoding: .utf8) ?? ""
        XCTAssertFalse(asText.contains(HookInstaller.marker))
    }

    func testUninstallClearsHooksKeyIfEmpty() throws {
        try installer.install()  // settings.json now only has our hooks
        try installer.uninstall()
        let settings = try readSettings()
        XCTAssertNil(settings["hooks"], "empty hooks tree should be removed entirely")
    }

    // MARK: - currentState

    func testCurrentStateBeforeInstall() {
        let state = installer.currentState()
        XCTAssertFalse(state.installed)
        XCTAssertFalse(state.matches)
    }

    func testCurrentStateAfterInstall() throws {
        try installer.install()
        let state = installer.currentState()
        XCTAssertTrue(state.installed)
        XCTAssertTrue(state.matches)
    }

    func testCurrentStateWhenPartiallyInstalled() throws {
        // Simulate an old install from a build that only registered 3 hook
        // events (e.g. before PreToolUse was added). installed=true because
        // projecthub entries exist; matches=false because we expect all of
        // the current hookEvents to be covered.
        try installer.install()
        var settings = try readSettings()
        var hooks = settings["hooks"] as! [String: Any]
        // Drop two of our events to fake a prior-version install.
        hooks.removeValue(forKey: "PreToolUse")
        hooks.removeValue(forKey: "PostToolUse")
        settings["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: settings, options: [])
            .write(to: settingsURL)

        let state = installer.currentState()
        XCTAssertTrue(state.installed, "some projecthub entries still present")
        XCTAssertFalse(state.matches, "not every expected event is covered")
    }

    func testCurrentStateAfterHandEditedCommand() throws {
        try installer.install()
        // Simulate the user renaming the script path in settings.json while
        // leaving our marker intact — installed=true, matches=false.
        var settings = try readSettings()
        var hooks = settings["hooks"] as! [String: Any]
        var stop = hooks["Stop"] as! [[String: Any]]
        var entries = stop[0]["hooks"] as! [[String: Any]]
        entries[0]["command"] = "bash '/moved/path/script.sh' \(HookInstaller.marker)"
        stop[0]["hooks"] = entries
        hooks["Stop"] = stop
        settings["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: settings, options: [])
            .write(to: settingsURL)

        let state = installer.currentState()
        XCTAssertTrue(state.installed, "still marker-tagged, counts as installed")
        XCTAssertFalse(state.matches, "path drift should flag mismatch")
    }

    // MARK: - Idempotence

    func testInstallTwiceDoesNotDuplicate() throws {
        try installer.install()
        try installer.install()
        let settings = try readSettings()
        let hooks = settings["hooks"] as! [String: Any]
        for event in HookInstaller.hookEvents {
            let groups = hooks[event] as! [[String: Any]]
            XCTAssertEqual(groups.count, 1, "second install should replace, not append")
        }
    }
}
