import Foundation

/// Locates the `gh` CLI and checks authentication status.
/// Follows the same resolution strategy as `ClaudeCLI` — probe known paths
/// first, then fall back to the user's login shell.
public enum GitHubCLI {
    private static let lock = NSLock()
    private static var cachedResolvedPath: String?
    private static var cachedResolved = false

    public static func resolve() -> String? {
        lock.lock()
        defer { lock.unlock() }
        if cachedResolved { return cachedResolvedPath }
        cachedResolved = true
        cachedResolvedPath = probe()
        return cachedResolvedPath
    }

    public static func invalidateCache() {
        lock.lock()
        defer { lock.unlock() }
        cachedResolved = false
        cachedResolvedPath = nil
    }

    /// Returns true if `gh auth status` succeeds (user is logged in).
    public static func isAuthenticated() -> Bool {
        guard let ghPath = resolve() else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ghPath)
        process.arguments = ["auth", "status"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        process.environment = ["PATH": ClaudeCLI.augmentedPATH]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Private

    private static let knownPaths: [String] = {
        let home = NSHomeDirectory()
        return [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "\(home)/.local/bin/gh",
        ]
    }()

    private static func probe() -> String? {
        for candidate in knownPaths where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        if let resolved = runShellLookup(shell: shell) { return resolved }
        if shell != "/bin/zsh", let resolved = runShellLookup(shell: "/bin/zsh") { return resolved }
        return nil
    }

    private static func runShellLookup(shell: String) -> String? {
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", "command -v gh 2>/dev/null"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(2.0)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate(); return nil }
        guard let data = try? out.fileHandleForReading.readToEnd(),
              let s = String(data: data, encoding: .utf8)
        else { return nil }
        let lines = s.split(separator: "\n", omittingEmptySubsequences: true)
        guard let last = lines.last.map({ $0.trimmingCharacters(in: .whitespaces) }),
              !last.isEmpty,
              FileManager.default.isExecutableFile(atPath: last)
        else { return nil }
        return last
    }
}
