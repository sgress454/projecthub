import Foundation

/// Filesystem locations and rotation logic for the Claude hook event log.
/// The Swift app READS this file; the bash hook script (owned by
/// `HookInstaller`) is what APPENDS to it.
public enum EventLog {
    /// Canonical location: `~/Library/Application Support/ProjectHub/`.
    public static var directory: URL {
        let fm = FileManager.default
        let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = (appSupport ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support"))
            .appendingPathComponent("ProjectHub", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Full path to the live log file.
    public static var logURL: URL {
        directory.appendingPathComponent("events.jsonl")
    }

    /// Ensures the log file exists (empty) so a watcher can attach.
    public static func ensureExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: logURL.path) {
            fm.createFile(atPath: logURL.path, contents: nil)
        }
    }

    /// Rotates the log if it exceeds `maxSizeBytes`, keeping up to `keep`
    /// rotated copies (`events.jsonl.1` … `events.jsonl.<keep>`).
    /// Safe to call periodically; no-op if the file is under the threshold.
    @discardableResult
    public static func rotateIfNeeded(
        at directory: URL = directory,
        maxSizeBytes: Int = 10 * 1024 * 1024,
        keep: Int = 3
    ) -> Bool {
        let fm = FileManager.default
        let live = directory.appendingPathComponent("events.jsonl")
        guard let attr = try? fm.attributesOfItem(atPath: live.path),
              let size = attr[.size] as? Int,
              size >= maxSizeBytes
        else { return false }

        // Shift rotated files down: .(keep-1) → .keep, .(keep-2) → .(keep-1), …
        if keep >= 1 {
            // Drop the oldest if it exists.
            let toDrop = directory.appendingPathComponent("events.jsonl.\(keep)")
            try? fm.removeItem(at: toDrop)
            for i in stride(from: keep - 1, through: 1, by: -1) {
                let src = directory.appendingPathComponent("events.jsonl.\(i)")
                let dst = directory.appendingPathComponent("events.jsonl.\(i + 1)")
                try? fm.moveItem(at: src, to: dst)
            }
            let firstRotated = directory.appendingPathComponent("events.jsonl.1")
            try? fm.removeItem(at: firstRotated)
            try? fm.moveItem(at: live, to: firstRotated)
        } else {
            try? fm.removeItem(at: live)
        }
        // Recreate empty live file so watchers/appenders keep working.
        fm.createFile(atPath: live.path, contents: nil)
        return true
    }

    /// Decodes one `events.jsonl` line into a `HookEvent`. Returns nil if the
    /// line is blank, malformed, or references a hook event ProjectHub
    /// doesn't track (e.g. `PreToolUse`, `SessionStart`).
    public static func decode(line: String) -> HookEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(HookEvent.self, from: data)
    }
}
