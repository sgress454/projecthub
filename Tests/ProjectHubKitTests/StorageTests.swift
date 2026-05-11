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

    // MARK: - v0.1 file loads, re-saves with defaults populated

    func testLoadsV1FileAndReSavesWithDefaults() throws {
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
        // Metadata fields default to empty/nil on v1 files.
        XCTAssertTrue(store.projects[0].githubIssues.isEmpty)
        XCTAssertTrue(store.projects[0].githubPRs.isEmpty)
        XCTAssertTrue(store.projects[0].links.isEmpty)
        XCTAssertNil(store.projects[0].openspecChange)
        XCTAssertNil(store.projects[0].summary)

        store.setPath(id: store.projects[0].id, path: "/tmp/alpha")
        store.flushPendingSave()

        // Re-read from disk and check version + new fields round-tripped.
        let rawData = try Data(contentsOf: fileURL())
        let raw = try JSONSerialization.jsonObject(with: rawData) as! [String: Any]
        XCTAssertEqual(raw["version"] as? Int, 3)

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

    // MARK: - v2 file loads with metadata defaults

    func testLoadsV2FileWithMetadataDefaults() throws {
        let v2Payload: [String: Any] = [
            "version": 2,
            "projects": [
                [
                    "id": UUID().uuidString,
                    "name": "gamma",
                    "space": 3,
                    "path": "/tmp/gamma",
                    "claude_enabled": true,
                ],
            ],
            "settings": ["claude_hook_installed": true],
        ]
        let data = try JSONSerialization.data(withJSONObject: v2Payload, options: [])
        try data.write(to: fileURL())

        let store = ProjectStore(fileURL: fileURL())
        XCTAssertEqual(store.projects.count, 1)
        let project = store.projects[0]
        XCTAssertEqual(project.name, "gamma")
        XCTAssertEqual(project.path, "/tmp/gamma")
        XCTAssertTrue(project.claudeEnabled)
        // v2 files have no metadata — fields default to empty/nil.
        XCTAssertTrue(project.githubIssues.isEmpty)
        XCTAssertTrue(project.githubPRs.isEmpty)
        XCTAssertTrue(project.links.isEmpty)
        XCTAssertNil(project.openspecChange)
        XCTAssertNil(project.summary)
    }

    // MARK: - v3 metadata round-trips

    func testMetadataFieldsRoundTrip() throws {
        let store = ProjectStore(fileURL: fileURL())
        store.add(name: "proj", space: 1)
        let id = store.projects[0].id

        let issueURL = URL(string: "https://github.com/org/repo/issues/42")!
        let prURL = URL(string: "https://github.com/org/repo/pull/51")!
        let figmaURL = URL(string: "https://figma.com/design/abc123")!

        store.setGithubIssues(id: id, issues: [issueURL])
        store.setGithubPRs(id: id, prs: [
            GitHubPREntry(url: prURL, source: .auto),
        ])
        store.setLinks(id: id, links: [
            LabeledLink(url: figmaURL, label: "Design mockups"),
        ])
        store.setOpenspecChange(id: id, change: "add-dark-mode")
        store.setSummary(id: id, summary: "Working on dark mode. 3 of 5 tasks done.")
        store.flushPendingSave()

        // Reload from disk.
        let reloaded = ProjectStore(fileURL: fileURL())
        let project = reloaded.projects[0]
        XCTAssertEqual(project.githubIssues, [issueURL])
        XCTAssertEqual(project.githubPRs.count, 1)
        XCTAssertEqual(project.githubPRs[0].url, prURL)
        XCTAssertEqual(project.githubPRs[0].source, .auto)
        XCTAssertEqual(project.links.count, 1)
        XCTAssertEqual(project.links[0].url, figmaURL)
        XCTAssertEqual(project.links[0].label, "Design mockups")
        XCTAssertEqual(project.openspecChange, "add-dark-mode")
        XCTAssertEqual(project.summary, "Working on dark mode. 3 of 5 tasks done.")

        // Verify on-disk version.
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL())) as! [String: Any]
        XCTAssertEqual(raw["version"] as? Int, 3)
    }

    // MARK: - Empty metadata fields omitted from JSON

    func testEmptyMetadataOmittedFromJSON() throws {
        let store = ProjectStore(fileURL: fileURL())
        store.add(name: "proj", space: 1)
        store.flushPendingSave()

        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL())) as! [String: Any]
        let persisted = (raw["projects"] as! [[String: Any]])[0]
        XCTAssertNil(persisted["github_issues"])
        XCTAssertNil(persisted["github_prs"])
        XCTAssertNil(persisted["links"])
        XCTAssertNil(persisted["openspec_change"])
        XCTAssertNil(persisted["summary"])
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

    // MARK: - nextAvailableSpace range

    func testNextAvailableSpaceReturns10WhenSpaces1Through9AreUsed() {
        let store = ProjectStore(fileURL: fileURL())
        for n in 1 ... 9 {
            store.add(name: "p\(n)", space: n)
        }
        XCTAssertEqual(store.nextAvailableSpace(), 10)
    }

    func testNextAvailableSpaceFindsFirstGapUpTo16() {
        let store = ProjectStore(fileURL: fileURL())
        // Occupy 1..12, leaving 13 as the lowest free slot.
        for n in 1 ... 12 {
            store.add(name: "p\(n)", space: n)
        }
        XCTAssertEqual(store.nextAvailableSpace(), 13)
    }

    func testNextAvailableSpaceFallsBackTo1WhenAll16AreOccupied() {
        let store = ProjectStore(fileURL: fileURL())
        for n in 1 ... 16 {
            store.add(name: "p\(n)", space: n)
        }
        XCTAssertEqual(store.nextAvailableSpace(), 1)
    }

    // MARK: - space_id64 round-trip

    func testSpaceID64RoundTrips() throws {
        let store = ProjectStore(fileURL: fileURL())
        store.add(name: "proj", space: 2)
        let id = store.projects[0].id
        store.setSpace(id: id, space: 2, spaceID64: 0xDEAD_BEEF_CAFE)
        store.flushPendingSave()

        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL())) as! [String: Any]
        let persisted = (raw["projects"] as! [[String: Any]])[0]
        XCTAssertEqual((persisted["space_id64"] as? NSNumber)?.uint64Value, 0xDEAD_BEEF_CAFE)

        let reloaded = ProjectStore(fileURL: fileURL())
        XCTAssertEqual(reloaded.projects.first?.spaceID64, 0xDEAD_BEEF_CAFE)
    }

    func testPreUpgradeFilesLoadWithoutSpaceID64() throws {
        // A v3 file written before stable-space-tracking has no space_id64 field.
        let payload: [String: Any] = [
            "version": 3,
            "projects": [
                ["id": UUID().uuidString, "name": "alpha", "space": 1],
            ],
        ]
        try JSONSerialization.data(withJSONObject: payload, options: []).write(to: fileURL())

        let store = ProjectStore(fileURL: fileURL())
        XCTAssertEqual(store.projects.count, 1)
        XCTAssertNil(store.projects[0].spaceID64)
    }

    func testSpaceID64NilOmittedFromJSON() throws {
        let store = ProjectStore(fileURL: fileURL())
        store.add(name: "proj", space: 1)
        store.flushPendingSave()

        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL())) as! [String: Any]
        let persisted = (raw["projects"] as! [[String: Any]])[0]
        XCTAssertNil(persisted["space_id64"])
    }

    // MARK: - Archive round-trip (v4)

    func testArchiveRoundTripPreservesMetadataAndStripsSpaceFields() throws {
        let store = ProjectStore(fileURL: fileURL())
        store.add(name: "wrap-up", space: 4)
        let id = store.projects[0].id
        store.setPath(id: id, path: "/Users/scott/old-project")
        store.setClaudeEnabled(id: id, enabled: true)
        store.setSpace(id: id, space: 4, spaceID64: 0xABCD)
        store.setLinks(id: id, links: [
            LabeledLink(url: URL(string: "https://example.com")!, label: "docs"),
        ])
        store.setOpenspecChange(id: id, change: "old-change")
        store.setSummary(id: id, summary: "Wrapping up.")

        store.archive(id: id)
        store.flushPendingSave()

        let reloaded = ProjectStore(fileURL: fileURL())
        let project = reloaded.projects[0]
        XCTAssertTrue(project.archived)
        XCTAssertNotNil(project.archivedAt)
        XCTAssertEqual(project.space, 0, "archive sets space to 0 sentinel")
        XCTAssertNil(project.spaceID64)
        XCTAssertNil(project.path)
        XCTAssertFalse(project.claudeEnabled)
        // Metadata preserved.
        XCTAssertEqual(project.name, "wrap-up")
        XCTAssertEqual(project.links.count, 1)
        XCTAssertEqual(project.openspecChange, "old-change")
        XCTAssertEqual(project.summary, "Wrapping up.")
    }

    func testRestoreRoundTripClearsArchiveFields() throws {
        let store = ProjectStore(fileURL: fileURL())
        store.add(name: "back", space: 2)
        let id = store.projects[0].id
        store.archive(id: id)
        store.flushPendingSave()

        // Confirm archive landed before restore.
        let mid = ProjectStore(fileURL: fileURL())
        XCTAssertTrue(mid.projects[0].archived)

        mid.restore(id: id)
        mid.flushPendingSave()

        let reloaded = ProjectStore(fileURL: fileURL())
        let project = reloaded.projects[0]
        XCTAssertFalse(project.archived)
        XCTAssertNil(project.archivedAt)
        // space stays at 0 (unassigned-active) — user picks a Space via the picker.
        XCTAssertEqual(project.space, 0)
        XCTAssertNil(project.spaceID64)
    }

    func testPreArchiveFilesLoadWithoutArchivedFields() throws {
        // A v3 file written before archive-project has no archived / archived_at.
        let payload: [String: Any] = [
            "version": 3,
            "projects": [
                ["id": UUID().uuidString, "name": "legacy", "space": 1],
            ],
        ]
        try JSONSerialization.data(withJSONObject: payload, options: []).write(to: fileURL())

        let store = ProjectStore(fileURL: fileURL())
        XCTAssertEqual(store.projects.count, 1)
        XCTAssertFalse(store.projects[0].archived)
        XCTAssertNil(store.projects[0].archivedAt)
    }

    func testArchivedFieldsOmittedFromJSONWhenDefault() throws {
        let store = ProjectStore(fileURL: fileURL())
        store.add(name: "fresh", space: 1)
        store.flushPendingSave()

        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL())) as! [String: Any]
        let persisted = (raw["projects"] as! [[String: Any]])[0]
        XCTAssertNil(persisted["archived"])
        XCTAssertNil(persisted["archived_at"])
    }

    func testArchivedProjectsSortedLastArchivedFirst() throws {
        let store = ProjectStore(fileURL: fileURL())
        store.add(name: "first", space: 1)
        store.add(name: "second", space: 2)
        store.add(name: "third", space: 3)
        let firstID = store.projects[0].id
        let secondID = store.projects[1].id
        let thirdID = store.projects[2].id

        // Archive in order: first, then second, then third.
        // ProjectStore.archive uses Date() internally so we need real time
        // gaps; sleep briefly between archives to keep timestamps strict.
        store.archive(id: firstID)
        Thread.sleep(forTimeInterval: 0.01)
        store.archive(id: secondID)
        Thread.sleep(forTimeInterval: 0.01)
        store.archive(id: thirdID)
        store.flushPendingSave()

        let reloaded = ProjectStore(fileURL: fileURL())
        let archivedNames = reloaded.archivedProjects.map(\.name)
        XCTAssertEqual(archivedNames, ["third", "second", "first"])
    }

    func testActiveProjectsExcludesArchived() throws {
        let store = ProjectStore(fileURL: fileURL())
        store.add(name: "keep", space: 1)
        store.add(name: "shelve", space: 2)
        let shelveID = store.projects[1].id
        store.archive(id: shelveID)
        store.flushPendingSave()

        XCTAssertEqual(store.activeProjects.map(\.name), ["keep"])
        XCTAssertEqual(store.archivedProjects.map(\.name), ["shelve"])
        XCTAssertEqual(store.projects.count, 2, "underlying storage retains both")
    }
}
