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
        process.environment = Self.ghEnvironment()
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

    private static func ghEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ClaudeCLI.augmentedPATH
        return env
    }

    private func fetchPRInfo(repo: String, number: Int, url: URL) -> GitHubPRInfo {
        let fallback = GitHubPRInfo(number: number, title: "#\(number)", url: url, state: "OPEN")
        guard let ghPath = GitHubCLI.resolve() else { return fallback }

        // Basic PR metadata via gh pr view.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ghPath)
        process.arguments = [
            "pr", "view", "\(number)",
            "--repo", repo,
            "--json", "number,title,url,state,isDraft,reviewDecision,assignees,author",
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.environment = Self.ghEnvironment()
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return fallback }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return fallback }

            let title = dict["title"] as? String ?? "#\(number)"
            let state = dict["state"] as? String ?? "OPEN"
            let isDraft = dict["isDraft"] as? Bool ?? false
            let reviewDecision = dict["reviewDecision"] as? String ?? ""
            let assignees = dict["assignees"] as? [[String: Any]] ?? []
            let authorLogin = (dict["author"] as? [String: Any])?["login"] as? String ?? ""

            // Unresolved review thread count via GraphQL.
            let unresolvedCount = fetchUnresolvedThreadCount(
                ghPath: ghPath, repo: repo, number: number, excludeAuthor: authorLogin
            )

            return GitHubPRInfo(
                number: number, title: title, url: url, state: state,
                isDraft: isDraft, reviewDecision: reviewDecision,
                hasAssignees: !assignees.isEmpty, unresolvedCommentCount: unresolvedCount
            )
        } catch {
            return fallback
        }
    }

    /// Uses the GitHub GraphQL API to count unresolved review threads,
    /// excluding threads started by the PR author.
    private func fetchUnresolvedThreadCount(ghPath: String, repo: String, number: Int, excludeAuthor: String) -> Int {
        let parts = repo.split(separator: "/")
        guard parts.count == 2 else { return 0 }
        let owner = parts[0]
        let name = parts[1]

        let query = """
        query {
          repository(owner: "\(owner)", name: "\(name)") {
            pullRequest(number: \(number)) {
              reviewThreads(first: 100) {
                nodes {
                  isResolved
                  comments(first: 1) {
                    nodes { author { login } }
                  }
                }
              }
            }
          }
        }
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ghPath)
        process.arguments = ["api", "graphql", "-f", "query=\(query)"]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.environment = Self.ghEnvironment()
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return 0 }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataDict = root["data"] as? [String: Any],
                  let repoDict = dataDict["repository"] as? [String: Any],
                  let prDict = repoDict["pullRequest"] as? [String: Any],
                  let threads = prDict["reviewThreads"] as? [String: Any],
                  let nodes = threads["nodes"] as? [[String: Any]]
            else { return 0 }

            var count = 0
            for node in nodes {
                guard node["isResolved"] as? Bool == false else { continue }
                // Exclude threads started by the PR author.
                if let comments = node["comments"] as? [String: Any],
                   let commentNodes = comments["nodes"] as? [[String: Any]],
                   let first = commentNodes.first,
                   let author = first["author"] as? [String: Any],
                   let login = author["login"] as? String,
                   login == excludeAuthor {
                    continue
                }
                count += 1
            }
            return count
        } catch {
            return 0
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
