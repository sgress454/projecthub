import Foundation
import ProjectHubKit

/// Periodically discovers PRs for each project by branch and caches PR metadata.
/// Runs `gh` CLI in the background; silently disabled when `gh` is absent.
final class GitHubSync {
    static let shared = GitHubSync()

    /// In-memory cache of PR metadata keyed by PR URL.
    private(set) var prInfoCache: [URL: GitHubPRInfo] = [:]

    private var timer: Timer?
    private let queue = DispatchQueue(label: "GitHubSync", qos: .utility)

    /// Callback fired after each sync cycle so the app can rebuild the menu
    /// and trigger summary regeneration.
    var onSyncComplete: ((_ changed: Bool) -> Void)?

    func start() {
        // Immediate first sync.
        triggerSync()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func triggerSync() {
        queue.async { [weak self] in
            guard let self else { return }
            let changed = self.runSync()
            self.scheduleNext()
            DispatchQueue.main.async {
                self.onSyncComplete?(changed)
            }
        }
    }

    // MARK: - Private

    private func scheduleNext() {
        let hasOpenPRs = !prInfoCache.isEmpty && prInfoCache.values.contains(where: { $0.state == "OPEN" })
        let interval: TimeInterval = hasOpenPRs ? 300 : 900 // 5 min / 15 min
        DispatchQueue.main.async { [weak self] in
            self?.timer?.invalidate()
            self?.timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                self?.triggerSync()
            }
        }
    }

    /// Returns true if any project's PR data changed.
    private func runSync() -> Bool {
        guard GitHubCLI.resolve() != nil else { return false }

        let projects = DispatchQueue.main.sync { ProjectStore.shared.projects }
        var newCache: [URL: GitHubPRInfo] = [:]
        var anyProjectChanged = false

        for project in projects {
            guard let path = project.path else { continue }
            guard let branch = gitCurrentBranch(at: path) else { continue }
            guard let remote = gitRemoteURL(at: path) else { continue }
            guard let repo = parseGitHubRepo(from: remote) else { continue }

            let discovered = discoverPRs(repo: repo, branch: branch)
            for pr in discovered {
                let info = fetchPRInfo(repo: repo, number: pr.number, url: pr.url)
                newCache[pr.url] = info
            }

            // Merge auto-discovered with existing manual PRs.
            let discoveredURLs = Set(discovered.map(\.url))
            let existingPRs = project.githubPRs
            var merged: [GitHubPREntry] = existingPRs.filter { $0.source == .manual }
            for pr in discovered {
                if !merged.contains(where: { $0.url == pr.url }) {
                    merged.append(GitHubPREntry(url: pr.url, source: .auto))
                }
            }
            // Remove stale auto-discovered entries.
            let previousAuto = existingPRs.filter { $0.source == .auto }.map(\.url)
            let removedAuto = Set(previousAuto).subtracting(discoveredURLs)
            if !removedAuto.isEmpty || Set(merged.map(\.url)) != Set(existingPRs.map(\.url)) {
                anyProjectChanged = true
                DispatchQueue.main.sync {
                    ProjectStore.shared.setGithubPRs(id: project.id, prs: merged)
                }
            }

            // Also cache info for manually-added PRs.
            for entry in merged where entry.source == .manual && newCache[entry.url] == nil {
                if let prNumber = Self.extractPRNumber(from: entry.url),
                   let prRepo = Self.extractRepo(from: entry.url) {
                    let info = fetchPRInfo(repo: prRepo, number: prNumber, url: entry.url)
                    newCache[entry.url] = info
                }
            }
        }

        let changed = anyProjectChanged || newCache.keys != prInfoCache.keys
        prInfoCache = newCache
        return changed
    }

    // MARK: - Git helpers

    private func gitCurrentBranch(at path: String) -> String? {
        runGit(at: path, args: ["branch", "--show-current"])
    }

    private func gitRemoteURL(at path: String) -> String? {
        runGit(at: path, args: ["remote", "get-url", "origin"])
    }

    private func runGit(at path: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", path] + args
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// Parse "org/repo" from a GitHub remote URL.
    private func parseGitHubRepo(from remote: String) -> String? {
        // Handles both HTTPS and SSH formats.
        // https://github.com/org/repo.git  →  org/repo
        // git@github.com:org/repo.git      →  org/repo
        var s = remote
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        if s.contains("github.com") {
            if let url = URL(string: s), url.pathComponents.count >= 3 {
                return "\(url.pathComponents[1])/\(url.pathComponents[2])"
            }
            // SSH format
            if let colonIdx = s.lastIndex(of: ":") {
                return String(s[s.index(after: colonIdx)...])
            }
        }
        return nil
    }

    // MARK: - gh CLI helpers

    private struct DiscoveredPR {
        let number: Int
        let url: URL
    }

    private func discoverPRs(repo: String, branch: String) -> [DiscoveredPR] {
        guard let ghPath = GitHubCLI.resolve() else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ghPath)
        process.arguments = [
            "pr", "list",
            "--head", branch,
            "--repo", repo,
            "--json", "number,url",
            "--state", "all",
            "--limit", "20",
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.environment = ["PATH": ClaudeCLI.augmentedPATH]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
            return arr.compactMap { dict in
                guard let number = dict["number"] as? Int,
                      let urlString = dict["url"] as? String,
                      let url = URL(string: urlString)
                else { return nil }
                return DiscoveredPR(number: number, url: url)
            }
        } catch {
            return []
        }
    }

    private func fetchPRInfo(repo: String, number: Int, url: URL) -> GitHubPRInfo {
        guard let ghPath = GitHubCLI.resolve() else {
            return GitHubPRInfo(number: number, title: "#\(number)", url: url, state: "OPEN", unresolvedCommentCount: 0)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ghPath)
        process.arguments = [
            "pr", "view", "\(number)",
            "--repo", repo,
            "--json", "number,title,url,state,author,reviews,comments",
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.environment = ["PATH": ClaudeCLI.augmentedPATH]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return GitHubPRInfo(number: number, title: "#\(number)", url: url, state: "OPEN", unresolvedCommentCount: 0)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return GitHubPRInfo(number: number, title: "#\(number)", url: url, state: "OPEN", unresolvedCommentCount: 0)
            }
            let title = dict["title"] as? String ?? "#\(number)"
            let state = dict["state"] as? String ?? "OPEN"
            let authorLogin = (dict["author"] as? [String: Any])?["login"] as? String ?? ""

            // Count unresolved comments not by the PR author.
            var unresolvedCount = 0
            if let comments = dict["comments"] as? [[String: Any]] {
                for comment in comments {
                    let login = (comment["author"] as? [String: Any])?["login"] as? String ?? ""
                    if login != authorLogin {
                        unresolvedCount += 1
                    }
                }
            }
            if let reviews = dict["reviews"] as? [[String: Any]] {
                for review in reviews {
                    let login = (review["author"] as? [String: Any])?["login"] as? String ?? ""
                    if login != authorLogin, let body = review["body"] as? String, !body.isEmpty {
                        unresolvedCount += 1
                    }
                }
            }

            return GitHubPRInfo(number: number, title: title, url: url, state: state, unresolvedCommentCount: unresolvedCount)
        } catch {
            return GitHubPRInfo(number: number, title: "#\(number)", url: url, state: "OPEN", unresolvedCommentCount: 0)
        }
    }

    // MARK: - URL parsing helpers

    static func extractPRNumber(from url: URL) -> Int? {
        let components = url.pathComponents
        guard let idx = components.firstIndex(of: "pull"),
              idx + 1 < components.count
        else { return nil }
        return Int(components[idx + 1])
    }

    static func extractRepo(from url: URL) -> String? {
        // https://github.com/org/repo/pull/N  →  org/repo
        let components = url.pathComponents
        guard components.count >= 4,
              let host = url.host, host.contains("github.com")
        else { return nil }
        return "\(components[1])/\(components[2])"
    }
}
