import Foundation
import XCTest
@testable import ProjectHubKit

final class StorageTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ProjectHubTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func fileURL() -> URL { tempDir.appendingPathComponent("projects.json") }

    // MARK: - 1.4: v0.1 file loads, re-saves as v2, defaults populated

    func testLoadsV1FileAndReSavesAsV2WithDefaults() throws {
        // Seed a v0.1-shaped projects.json on disk.
        let v1Payload: [String: Any] = [
            "version": 1,
            "projects": [
                ["id": UUID().uuidString, "name": "alpha", "space": 1],
                ["id": UUID().uuidString, "name": "beta", "space": 2],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: v1Payload, options: [])
        try data.write(to: fileURL())

        // Load via the store and mutate to trigger a save.
        let store = ProjectStore(fileURL: fileURL())
        XCTAssertEqual(store.projects.count, 2)
        XCTAssertEqual(store.projects[0].name, "alpha")
        XCTAssertNil(store.projects[0].path)
        XCTAssertFalse(store.projects[0].claudeEnabled)
        XCTAssertFalse(store.settings.claudeHookInstalled)

        store.setPath(id: store.projects[0].id, path: "/tmp/alpha")
        store.flushPendingSave()

        // Re-read from disk and check version + new fields round-tripped.
        let rawData = try Data(contentsOf: fileURL())
        let raw = try JSONSerialization.jsonObject(with: rawData) as! [String: Any]
        XCTAssertEqual(raw["version"] as? Int, 2)

        let persisted = raw["projects"] as! [[String: Any]]
        XCTAssertEqual(persisted.count, 2)
        let alpha = persisted.first { ($0["name"] as? String) == "alpha" }!
        XCTAssertEqual(alpha["path"] as? String, "/tmp/alpha")
        XCTAssertEqual(alpha["claude_enabled"] as? Bool, false)

        let settings = raw["settings"] as! [String: Any]
        XCTAssertEqual(settings["claude_hook_installed"] as? Bool, false)
    }

    // MARK: - 1.4: unknown fields round-trip without loss

    func testUnknownFieldsRoundTrip() throws {
        let unknownProjectField = "future_v3_flag"
        let unknownTopLevelField = "future_top_level"

        let v1Payload: [String: Any] = [
            "version": 1,
            unknownTopLevelField: ["some": "value"],
            "projects": [
                [
                    "id": UUID().uuidString,
                    "name": "alpha",
                    "space": 1,
                    unknownProjectField: 42,
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: v1Payload, options: [])
        try data.write(to: fileURL())

        let store = ProjectStore(fileURL: fileURL())
        store.update(id: store.projects[0].id, name: "alpha-renamed")
        store.flushPendingSave()

        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL())) as! [String: Any]
        XCTAssertNotNil(raw[unknownTopLevelField])
        let persisted = raw["projects"] as! [[String: Any]]
        XCTAssertEqual(persisted[0][unknownProjectField] as? Int, 42)
        XCTAssertEqual(persisted[0]["name"] as? String, "alpha-renamed")
    }

    // MARK: - 1.1 / 1.2: new fields persist

    func testPathAndClaudeEnabledPersist() throws {
        let store = ProjectStore(fileURL: fileURL())
        store.add(name: "proj", space: 1)
        let id = store.projects[0].id
        store.setPath(id: id, path: "/Users/scott/Development/proj")
        store.setClaudeEnabled(id: id, enabled: true)
        store.setClaudeHookInstalled(true)
        store.flushPendingSave()

        let reloaded = ProjectStore(fileURL: fileURL())
        XCTAssertEqual(reloaded.projects.first?.path, "/Users/scott/Development/proj")
        XCTAssertEqual(reloaded.projects.first?.claudeEnabled, true)
        XCTAssertEqual(reloaded.settings.claudeHookInstalled, true)
    }

    func testClearingPathRemovesFieldFromJSON() throws {
        let store = ProjectStore(fileURL: fileURL())
        store.add(name: "proj", space: 1)
        let id = store.projects[0].id
        store.setPath(id: id, path: "/some/path")
        store.flushPendingSave()

        store.setPath(id: id, path: nil)
        store.flushPendingSave()

        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL())) as! [String: Any]
        let persisted = (raw["projects"] as! [[String: Any]])[0]
        XCTAssertNil(persisted["path"])
    }
}
