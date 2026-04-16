import Foundation

/// Manages the Claude Code hook that feeds ProjectHub its event stream.
/// Reads, mutates, and writes `~/.claude/settings.json`. Preserves hooks
/// the user has configured themselves; identifies its own entries via a
/// `# projecthub-managed` comment tacked onto the command.
///
/// Atomic writes via `.atomic` (temp + rename). Reversible via `uninstall()`.
public struct HookInstaller {
    /// Sentinel string appended to every command we own. Survives JSON
    /// round-trip and is ignored by bash at execution time.
    public static let marker = "# projecthub-managed"

    /// The five Claude hook event types ProjectHub subscribes to.
    /// `PreToolUse` matters for fast red→green transitions — the moment
    /// a permission is approved and the tool is about to run, state clears.
    public static let hookEvents: [String] = [
        "Stop", "Notification", "UserPromptSubmit", "PreToolUse", "PostToolUse",
    ]

    public var settingsURL: URL
    public var hookScriptURL: URL
    public var fileManager: FileManager

    public init(
        settingsURL: URL = URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent(".claude/settings.json")),
        hookScriptURL: URL = EventLog.directory.appendingPathComponent("hooks/projecthub-event.sh"),
        fileManager: FileManager = .default
    ) {
        self.settingsURL = settingsURL
        self.hookScriptURL = hookScriptURL
        self.fileManager = fileManager
    }

    // MARK: - Hook script

    /// Bash script written to disk that forwards every Claude hook event as
    /// one JSON line into `events.jsonl`. Deliberately five lines and
    /// protected by `exec >/dev/null 2>&1` so a failure can never surface
    /// into the originating Claude session.
    public static let hookScript: String = #"""
    #!/bin/bash
    # projecthub-managed
    exec >/dev/null 2>&1
    LOG="$HOME/Library/Application Support/ProjectHub/events.jsonl"
    mkdir -p "$(dirname "$LOG")"
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    payload=$(cat)
    printf '{"ts":"%s",%s\n' "$ts" "${payload#\{}" >> "$LOG"
    """#

    /// Exact command string the installer writes into settings.json. Any
    /// deviation (a user hand-edited the path, for example) will show up as
    /// `State.matches == false` even if `State.installed == true`.
    public func expectedCommand() -> String {
        "bash '\(hookScriptURL.path)' \(Self.marker)"
    }

    // MARK: - State introspection

    public struct State: Equatable {
        public var installed: Bool
        public var matches: Bool

        public static let notInstalled = State(installed: false, matches: false)
    }

    public func currentState() -> State {
        guard let settings = readSettings(),
              let hooks = settings["hooks"] as? [String: Any]
        else { return .notInstalled }

        // Count how many of this build's expected events are covered by a
        // projecthub-tagged command, and separately how many match the
        // exact command string. "Installed" means the user has asked for
        // the hook at some point (some tagged entry exists); "matches"
        // means every expected event has the exact expected command, so
        // the install is fully current.
        var markedEvents = Set<String>()
        var matchedEvents = Set<String>()
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            for group in groups {
                guard let entries = group["hooks"] as? [[String: Any]] else { continue }
                for entry in entries {
                    guard let cmd = entry["command"] as? String,
                          cmd.contains(Self.marker)
                    else { continue }
                    markedEvents.insert(event)
                    if cmd == expectedCommand() { matchedEvents.insert(event) }
                }
            }
        }
        let expectedSet = Set(Self.hookEvents)
        return State(
            installed: !markedEvents.isEmpty,
            matches: matchedEvents == expectedSet
        )
    }

    // MARK: - Install / uninstall

    public func install() throws {
        try writeHookScript()
        var settings = readSettings() ?? [:]
        var hooks = (settings["hooks"] as? [String: Any]) ?? [:]
        for event in Self.hookEvents {
            var groups = (hooks[event] as? [[String: Any]]) ?? []
            groups.removeAll { isOurGroup($0) }
            groups.append(ourGroup())
            hooks[event] = groups
        }
        settings["hooks"] = hooks
        try writeSettings(settings)
    }

    public func uninstall() throws {
        guard var settings = readSettings() else { return }
        guard var hooks = settings["hooks"] as? [String: Any] else { return }
        for event in Self.hookEvents {
            guard var groups = hooks[event] as? [[String: Any]] else { continue }
            groups.removeAll { isOurGroup($0) }
            if groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = groups
            }
        }
        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }
        try writeSettings(settings)
        // Leave the hook script on disk. A Claude session that triggers mid-
        // uninstall will just find an event file with a stale last line; the
        // next uninstall attempt still works because settings.json is the
        // source of truth for whether the hook fires.
    }

    /// Returns `(before, after)` pretty-printed JSON for a confirmation
    /// dialog. Does not write anything.
    public func previewInstall() -> (before: String, after: String) {
        let before: String
        if let data = try? Data(contentsOf: settingsURL),
           let s = String(data: data, encoding: .utf8)
        {
            before = s
        } else {
            before = "{}"
        }

        var after = readSettings() ?? [:]
        var hooks = (after["hooks"] as? [String: Any]) ?? [:]
        for event in Self.hookEvents {
            var groups = (hooks[event] as? [[String: Any]]) ?? []
            groups.removeAll { isOurGroup($0) }
            groups.append(ourGroup())
            hooks[event] = groups
        }
        after["hooks"] = hooks
        let afterData = (try? JSONSerialization.data(
            withJSONObject: after, options: [.prettyPrinted, .sortedKeys]
        )) ?? Data()
        return (before, String(data: afterData, encoding: .utf8) ?? "{}")
    }

    // MARK: - Internals

    private func isOurGroup(_ group: [String: Any]) -> Bool {
        guard let entries = group["hooks"] as? [[String: Any]] else { return false }
        return entries.contains { entry in
            (entry["command"] as? String)?.contains(Self.marker) == true
        }
    }

    private func ourGroup() -> [String: Any] {
        [
            "matcher": "",
            "hooks": [
                ["type": "command", "command": expectedCommand()],
            ],
        ]
    }

    private func readSettings() -> [String: Any]? {
        guard fileManager.fileExists(atPath: settingsURL.path) else { return nil }
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        try fileManager.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: settingsURL, options: [.atomic])
    }

    public func writeHookScript() throws {
        try fileManager.createDirectory(
            at: hookScriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.hookScript.write(to: hookScriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: hookScriptURL.path
        )
    }
}
