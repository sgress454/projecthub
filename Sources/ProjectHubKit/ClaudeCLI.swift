import Foundation

/// Locates the `claude` CLI from a process that was spawned by `launchd`
/// (e.g. a menu bar app). Such processes don't inherit a Terminal-style
/// PATH, so a plain `command -v claude` in the default environment
/// typically fails even when `claude` is clearly available in the user's
/// shell.
///
/// Strategy:
///   1. Probe a list of common install locations directly — fast, no shell.
///   2. Fall back to asking the user's shell (interactive + login so
///      .zshrc / .bash_profile PATH exports are picked up).
///
/// Also exposes the augmented PATH we install into child `claude`
/// invocations so that `claude`'s own spawned subprocesses (node, etc.)
/// can be found.
public enum ClaudeCLI {
    private static let lock = NSLock()
    private static var cachedResolvedPath: String?
    private static var cachedResolved = false

    /// Common install locations for the `claude` CLI, in priority order.
    public static var knownCandidatePaths: [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.local/bin/claude",
            "\(home)/.volta/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.yarn/bin/claude",
            "\(home)/.bun/bin/claude",
        ]
    }

    /// Resolves to an absolute path or nil if `claude` is nowhere we can
    /// find it. Cached for the process lifetime.
    public static func resolve() -> String? {
        lock.lock()
        defer { lock.unlock() }
        if cachedResolved { return cachedResolvedPath }
        cachedResolved = true
        cachedResolvedPath = probe()
        return cachedResolvedPath
    }

    /// Test-only: override the resolved path (or clear it with nil).
    public static func overridePath(_ path: String?) {
        lock.lock()
        defer { lock.unlock() }
        cachedResolved = true
        cachedResolvedPath = path
    }

    /// Invalidate the cache so the next `resolve()` probes again.
    public static func invalidateCache() {
        lock.lock()
        defer { lock.unlock() }
        cachedResolved = false
        cachedResolvedPath = nil
    }

    /// PATH environment variable to set when spawning `claude`. Starts with
    /// known bin directories so `claude`'s own subprocesses (node etc.) can
    /// find their dependencies even under a minimal launchd environment.
    public static var augmentedPATH: String {
        let home = NSHomeDirectory()
        let prepend = [
            "\(home)/.claude/local",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.volta/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.yarn/bin",
            "\(home)/.bun/bin",
        ]
        let existing = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let parts = prepend + (existing.isEmpty ? ["/usr/bin", "/bin", "/usr/sbin", "/sbin"] : [existing])
        return parts.joined(separator: ":")
    }

    // MARK: - Private probing

    private static func probe() -> String? {
        // 1. Known paths (fast, deterministic).
        for candidate in knownCandidatePaths where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        // 2. User's shell — LOGIN but NOT INTERACTIVE (`-lc`, not `-ilc`).
        //    Interactive zsh loads .zshrc → plugins → filesystem scans,
        //    which triggers TCC prompts for Photos / Music / Downloads.
        //    `-l` alone sources .zprofile / .zshenv which is where PATH
        //    *should* live anyway.
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        if let resolved = runShellLookup(shell: shell) {
            return resolved
        }
        if shell != "/bin/zsh", let resolved = runShellLookup(shell: "/bin/zsh") {
            return resolved
        }
        return nil
    }

    private static func runShellLookup(shell: String) -> String? {
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // -l (login) + -c (command). Deliberately no -i — see probe() above.
        process.arguments = ["-lc", "command -v claude 2>/dev/null"]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        // Cap at 2 s; interactive shells can be slow.
        let deadline = Date().addingTimeInterval(2.0)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        guard let data = try? out.fileHandleForReading.readToEnd(),
              let s = String(data: data, encoding: .utf8)
        else { return nil }
        // Interactive shells sometimes print other things first; take the
        // LAST non-empty line, which is `command -v`'s output.
        let lines = s.split(separator: "\n", omittingEmptySubsequences: true)
        guard let last = lines.last.map({ $0.trimmingCharacters(in: .whitespaces) }),
              !last.isEmpty,
              FileManager.default.isExecutableFile(atPath: last)
        else { return nil }
        return last
    }
}
