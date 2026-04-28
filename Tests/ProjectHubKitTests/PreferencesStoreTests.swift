import Foundation
import XCTest
@testable import ProjectHubKit

final class PreferencesStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ProjectHubPrefs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func fileURL() -> URL { tempDir.appendingPathComponent("preferences.json") }

    // MARK: - First-launch defaults

    func testFirstLaunchDetectsITerm2AndPersists() throws {
        let store = PreferencesStore(fileURL: fileURL(), detectInstalled: { _ in true })
        XCTAssertEqual(store.preferences.terminalApp, .iterm2)

        // File must exist immediately on first load.
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL().path))

        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL())) as! [String: Any]
        XCTAssertEqual(raw["terminal_app"] as? String, "iterm2")
        XCTAssertEqual(raw["version"] as? Int, 1)
    }

    func testFirstLaunchFallsBackToTerminalWhenITerm2Missing() throws {
        let store = PreferencesStore(fileURL: fileURL(), detectInstalled: { _ in false })
        XCTAssertEqual(store.preferences.terminalApp, .terminal)

        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL())) as! [String: Any]
        XCTAssertEqual(raw["terminal_app"] as? String, "terminal")
    }

    // MARK: - Verbatim read (no re-detection)

    func testExistingFileIsReadVerbatim() throws {
        // Seed a preferences.json saying "terminal" even though our detector
        // claims iTerm2 is installed. The stored value must win.
        let payload: [String: Any] = ["version": 1, "terminal_app": "terminal"]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        try data.write(to: fileURL())

        let store = PreferencesStore(fileURL: fileURL(), detectInstalled: { _ in true })
        XCTAssertEqual(store.preferences.terminalApp, .terminal)
    }

    // MARK: - Unknown fields round-trip

    func testUnknownFieldsRoundTrip() throws {
        let payload: [String: Any] = [
            "version": 1,
            "terminal_app": "iterm2",
            "future_top_level": ["a": 1],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        try data.write(to: fileURL())

        let store = PreferencesStore(fileURL: fileURL(), detectInstalled: { _ in false })
        store.setTerminalApp(.terminal)
        store.flushPendingSave()

        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL())) as! [String: Any]
        XCTAssertEqual(raw["terminal_app"] as? String, "terminal")
        XCTAssertNotNil(raw["future_top_level"])
    }

    // MARK: - Setter triggers persistence

    func testSetTerminalAppPersists() throws {
        let store = PreferencesStore(fileURL: fileURL(), detectInstalled: { _ in false })
        XCTAssertEqual(store.preferences.terminalApp, .terminal)

        store.setTerminalApp(.iterm2)
        store.flushPendingSave()

        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL())) as! [String: Any]
        XCTAssertEqual(raw["terminal_app"] as? String, "iterm2")
    }

    // MARK: - iTerm hotkey shortcut round-trip

    func testITermHotkeyShortcutRoundTripsAcrossRestart() throws {
        let store = PreferencesStore(fileURL: fileURL(), detectInstalled: { _ in false })
        XCTAssertNil(store.preferences.iTermHotkeyShortcut)

        // Record ⌃⌥⌘T (modifier mask example: arbitrary distinguishable value).
        let shortcut = RecordedShortcut(keyCode: 0x11, modifierFlags: 0x140000 | 0x80000 | 0x100000)
        store.setITermHotkeyShortcut(shortcut)
        store.flushPendingSave()

        // Simulate restart by re-creating the store on the same file.
        let store2 = PreferencesStore(fileURL: fileURL(), detectInstalled: { _ in false })
        XCTAssertEqual(store2.preferences.iTermHotkeyShortcut, shortcut)
    }

    func testClearingITermHotkeyShortcutRemovesField() throws {
        let store = PreferencesStore(fileURL: fileURL(), detectInstalled: { _ in false })
        store.setITermHotkeyShortcut(RecordedShortcut(keyCode: 17, modifierFlags: 0x100000))
        store.flushPendingSave()

        store.setITermHotkeyShortcut(nil)
        store.flushPendingSave()

        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL())) as! [String: Any]
        XCTAssertNil(raw["iterm_hotkey_shortcut"])
    }

    func testUnsetShortcutDoesNotWriteField() throws {
        let store = PreferencesStore(fileURL: fileURL(), detectInstalled: { _ in false })
        store.flushPendingSave()
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL())) as! [String: Any]
        XCTAssertNil(raw["iterm_hotkey_shortcut"])
        XCTAssertNil(store.preferences.iTermHotkeyShortcut)
    }
}
