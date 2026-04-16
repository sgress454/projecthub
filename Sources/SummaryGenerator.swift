import Foundation
import ProjectHubKit

/// Generates AI summaries for projects by invoking `claude -p` with gathered context.
/// Summaries are cached on the project and persisted to disk.
final class SummaryGenerator {
    static let shared = SummaryGenerator()

    private let queue = DispatchQueue(label: "SummaryGenerator", qos: .utility)
    /// Per-project debounce timers.
    private var pendingTimers: [UUID: DispatchWorkItem] = [:]
    private static let debounceInterval: TimeInterval = 5.0

    func start() {
        // Generate summaries for all projects that have enough context.
        regenerateAll()
    }

    /// Schedule regeneration for a specific project, debounced.
    func regenerate(projectId: UUID) {
        pendingTimers[projectId]?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.doGenerate(projectId: projectId)
        }
        pendingTimers[projectId] = item
        queue.asyncAfter(deadline: .now() + Self.debounceInterval, execute: item)
    }

    /// Regenerate summaries for all projects that have context.
    func regenerateAll() {
        let projects: [Project]
        if Thread.isMainThread {
            projects = ProjectStore.shared.projects
        } else {
            projects = DispatchQueue.main.sync { ProjectStore.shared.projects }
        }
        for project in projects {
            regenerate(projectId: project.id)
        }
    }

    // MARK: - Private

    private func doGenerate(projectId: UUID) {
        let project = DispatchQueue.main.sync {
            ProjectStore.shared.projects.first { $0.id == projectId }
        }
        guard let project else { return }

        let context = gatherContext(for: project)
        if context.isEmpty {
            DispatchQueue.main.async {
                ProjectStore.shared.setSummary(id: projectId, summary: nil)
            }
            return
        }

        guard let claudePath = ClaudeCLI.resolve() else {
            DispatchQueue.main.async {
                ProjectStore.shared.setSummary(id: projectId, summary: nil)
            }
            return
        }

        let prompt = """
        You are summarizing the current state of a software project for a developer's \
        menu bar dashboard. Be brief (2-3 sentences max). Include: the project goal if \
        known, what's actively happening, and anything that needs attention (open PR \
        comments, blocked tasks). Do not use markdown formatting.

        Project: \(project.name)

        \(context)
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["-p", prompt, "--output-format", "text"]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.environment = ["PATH": ClaudeCLI.augmentedPATH]
        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            // 30-second timeout for summary generation.
            let deadline = Date().addingTimeInterval(30.0)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if process.isRunning {
                process.terminate()
                return
            }
            guard process.terminationStatus == 0 else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let summary = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !summary.isEmpty
            else { return }

            DispatchQueue.main.async {
                ProjectStore.shared.setSummary(id: projectId, summary: summary)
            }
        } catch {
            NSLog("[SummaryGenerator] claude invocation failed: \(error)")
        }
    }

    private func gatherContext(for project: Project) -> String {
        var parts: [String] = []

        // Git log
        if let path = project.path {
            if let log = runGit(at: path, args: ["log", "--oneline", "-20"]) {
                parts.append("Recent commits:\n\(log)")
            }
        }

        // GitHub issues (just URLs for now; titles come from the submenu cache)
        if !project.githubIssues.isEmpty {
            let list = project.githubIssues.map { "- \($0.absoluteString)" }.joined(separator: "\n")
            parts.append("Linked GitHub issues:\n\(list)")
        }

        // PR info from cache
        let prCache = GitHubSync.shared.prInfoCache
        let prInfos = project.githubPRs.compactMap { prCache[$0.url] }
        if !prInfos.isEmpty {
            let list = prInfos.map { pr in
                var line = "- #\(pr.number) \(pr.title) [\(pr.state.lowercased())]"
                if pr.unresolvedCommentCount > 0 {
                    line += " — \(pr.unresolvedCommentCount) unresolved comment(s)"
                }
                return line
            }.joined(separator: "\n")
            parts.append("Pull requests:\n\(list)")
        }

        // OpenSpec context
        if let changeName = project.openspecChange, let path = project.path {
            let base = (path as NSString).appendingPathComponent("openspec/changes/\(changeName)")
            // Try active first, then archived
            let proposalPath = FileManager.default.fileExists(atPath: base + "/proposal.md")
                ? base + "/proposal.md"
                : findArchived(path: path, changeName: changeName, file: "proposal.md")
            let tasksPath = FileManager.default.fileExists(atPath: base + "/tasks.md")
                ? base + "/tasks.md"
                : findArchived(path: path, changeName: changeName, file: "tasks.md")

            if let pp = proposalPath, let content = try? String(contentsOfFile: pp, encoding: .utf8) {
                // Truncate to keep prompt reasonable.
                let truncated = String(content.prefix(2000))
                parts.append("OpenSpec proposal (\(changeName)):\n\(truncated)")
            }
            if let tp = tasksPath, let content = try? String(contentsOfFile: tp, encoding: .utf8) {
                let truncated = String(content.prefix(2000))
                parts.append("OpenSpec tasks (\(changeName)):\n\(truncated)")
            }
        }

        return parts.joined(separator: "\n\n")
    }

    private func findArchived(path: String, changeName: String, file: String) -> String? {
        let archiveDir = (path as NSString).appendingPathComponent("openspec/changes/archive")
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: archiveDir) else { return nil }
        // Archive names are like "2026-04-16-change-name"
        if let match = entries.first(where: { $0.hasSuffix(changeName) }) {
            let candidate = (archiveDir as NSString).appendingPathComponent("\(match)/\(file)")
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
        }
        return nil
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
}
