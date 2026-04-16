import Foundation
import XCTest
@testable import ProjectHubKit

final class EventLogTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ProjectHubEventLogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func writeLine(_ s: String, to url: URL) throws {
        let data = (s + "\n").data(using: .utf8)!
        if FileManager.default.fileExists(atPath: url.path) {
            let fh = try FileHandle(forWritingTo: url)
            try fh.seekToEnd()
            fh.write(data)
            try fh.close()
        } else {
            try data.write(to: url)
        }
    }

    // MARK: - Decode

    func testDecodeStopLine() throws {
        let line = #"{"ts":"2026-04-15T19:00:00Z","hook_event_name":"Stop","cwd":"/x","transcript_path":"/tmp/t.jsonl"}"#
        let event = EventLog.decode(line: line)
        XCTAssertEqual(event?.kind, .stop)
        XCTAssertEqual(event?.cwd, "/x")
        XCTAssertEqual(event?.transcriptPath, "/tmp/t.jsonl")
    }

    func testDecodeNotificationLine() throws {
        let line = #"{"ts":"2026-04-15T19:00:00Z","hook_event_name":"Notification","cwd":"/y"}"#
        let event = EventLog.decode(line: line)
        XCTAssertEqual(event?.kind, .notification)
        XCTAssertEqual(event?.cwd, "/y")
    }

    func testDecodeRejectsUnknownEventKind() {
        // Any hook event ProjectHub doesn't subscribe to should be ignored.
        let line = #"{"ts":"2026-04-15T19:00:00Z","hook_event_name":"SessionStart","cwd":"/x"}"#
        XCTAssertNil(EventLog.decode(line: line))
    }

    func testDecodeRejectsMalformed() {
        XCTAssertNil(EventLog.decode(line: "not json"))
        XCTAssertNil(EventLog.decode(line: ""))
        XCTAssertNil(EventLog.decode(line: "  "))
    }

    // MARK: - Rotation

    func testRotationMovesLiveFileToDot1AndEmptiesLive() throws {
        let live = tempDir.appendingPathComponent("events.jsonl")
        // Write 1 MB of bytes to force rotation at 500 KB threshold
        let junk = Data(repeating: 0x41, count: 1024 * 1024)
        try junk.write(to: live)

        let rotated = EventLog.rotateIfNeeded(at: tempDir, maxSizeBytes: 500 * 1024, keep: 3)
        XCTAssertTrue(rotated)

        let dot1 = tempDir.appendingPathComponent("events.jsonl.1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dot1.path))
        let liveSize = (try? FileManager.default.attributesOfItem(atPath: live.path)[.size] as? Int) ?? -1
        XCTAssertEqual(liveSize, 0, "live file should be empty after rotation")
    }

    func testRotationNoOpWhenUnderThreshold() throws {
        let live = tempDir.appendingPathComponent("events.jsonl")
        try Data(repeating: 0x41, count: 10).write(to: live)
        let rotated = EventLog.rotateIfNeeded(at: tempDir, maxSizeBytes: 1024, keep: 3)
        XCTAssertFalse(rotated)
    }

    func testRotationCascadesOldFiles() throws {
        let live = tempDir.appendingPathComponent("events.jsonl")
        let dot1 = tempDir.appendingPathComponent("events.jsonl.1")
        let dot2 = tempDir.appendingPathComponent("events.jsonl.2")
        try "live".data(using: .utf8)!.write(to: live)
        try "one".data(using: .utf8)!.write(to: dot1)
        try "two".data(using: .utf8)!.write(to: dot2)

        _ = EventLog.rotateIfNeeded(at: tempDir, maxSizeBytes: 1, keep: 3)

        // .1 should now hold previous live content ("live"), .2 the previous .1 ("one"),
        // .3 the previous .2 ("two").
        XCTAssertEqual(try String(contentsOf: dot1), "live")
        XCTAssertEqual(try String(contentsOf: dot2), "one")
        let dot3 = tempDir.appendingPathComponent("events.jsonl.3")
        XCTAssertEqual(try String(contentsOf: dot3), "two")
    }

    // MARK: - Watcher replay + live

    func testWatcherReplaysExistingEvents() throws {
        let live = tempDir.appendingPathComponent("events.jsonl")
        try writeLine(#"{"ts":"2026-04-15T19:00:00Z","hook_event_name":"Notification","cwd":"/a"}"#, to: live)
        try writeLine(#"{"ts":"2026-04-15T19:00:01Z","hook_event_name":"Stop","cwd":"/b"}"#, to: live)

        let events = expectEvents(count: 2) { handler in
            let watcher = EventLogWatcher(fileURL: live, queue: .main, handler: handler)
            watcher.startWithReplay()
            return watcher
        }
        XCTAssertEqual(events.map { $0.cwd }, ["/a", "/b"])
        XCTAssertEqual(events.map { $0.kind }, [.notification, .stop])
    }

    func testWatcherPicksUpNewAppends() throws {
        let live = tempDir.appendingPathComponent("events.jsonl")
        try writeLine(#"{"ts":"2026-04-15T19:00:00Z","hook_event_name":"Notification","cwd":"/a"}"#, to: live)

        let events = expectEvents(count: 2, timeout: 3.0) { handler in
            let watcher = EventLogWatcher(fileURL: live, queue: .main, handler: handler)
            watcher.startWithReplay()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                try? self.writeLine(
                    #"{"ts":"2026-04-15T19:00:05Z","hook_event_name":"Stop","cwd":"/c"}"#,
                    to: live
                )
            }
            return watcher
        }
        XCTAssertEqual(events.map { $0.cwd }, ["/a", "/c"])
    }

    // MARK: - Helpers

    /// Runs `setup` (which must start a watcher) and collects events until
    /// `count` have been received (or `timeout` fires). Returns them in order.
    private func expectEvents(
        count: Int,
        timeout: TimeInterval = 2.0,
        setup: ((@escaping (HookEvent) -> Void) -> EventLogWatcher)
    ) -> [HookEvent] {
        var collected: [HookEvent] = []
        let exp = expectation(description: "events")
        let handler: (HookEvent) -> Void = { event in
            collected.append(event)
            if collected.count >= count { exp.fulfill() }
        }
        let watcher = setup(handler)
        _ = watcher
        wait(for: [exp], timeout: timeout)
        watcher.stop()
        return collected
    }
}
