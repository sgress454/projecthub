import Foundation

public struct Project: Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var space: Int
    /// Filesystem directory associated with this project. Used to match incoming
    /// Claude Code hook events (via longest path-prefix) when `claudeEnabled` is true.
    public var path: String?
    /// Per-project opt-in for Claude state monitoring. No hook events for this
    /// project produce state changes while this is false.
    public var claudeEnabled: Bool
    /// Round-trip bucket for fields we don't recognize in the current schema.
    /// Preserving these keeps v0.1 files (and any future v0.3+ additions) intact.
    public var extraFields: [String: Any]

    // MARK: - Metadata fields (v3)

    public var githubIssues: [URL]
    public var githubPRs: [GitHubPREntry]
    public var links: [LabeledLink]
    public var openspecChange: String?
    public var summary: String?

    public init(
        id: UUID = UUID(),
        name: String,
        space: Int,
        path: String? = nil,
        claudeEnabled: Bool = false,
        extraFields: [String: Any] = [:],
        githubIssues: [URL] = [],
        githubPRs: [GitHubPREntry] = [],
        links: [LabeledLink] = [],
        openspecChange: String? = nil,
        summary: String? = nil
    ) {
        self.id = id
        self.name = name
        self.space = space
        self.path = path
        self.claudeEnabled = claudeEnabled
        self.extraFields = extraFields
        self.githubIssues = githubIssues
        self.githubPRs = githubPRs
        self.links = links
        self.openspecChange = openspecChange
        self.summary = summary
    }

    public static func == (lhs: Project, rhs: Project) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.space == rhs.space
            && lhs.path == rhs.path
            && lhs.claudeEnabled == rhs.claudeEnabled
            && lhs.githubIssues == rhs.githubIssues
            && lhs.githubPRs == rhs.githubPRs
            && lhs.links == rhs.links
            && lhs.openspecChange == rhs.openspecChange
            && lhs.summary == rhs.summary
    }

    public func toDictionary() -> [String: Any] {
        var dict = extraFields
        dict["name"] = name
        dict["space"] = space
        dict["id"] = id.uuidString
        if let path {
            dict["path"] = path
        } else {
            dict.removeValue(forKey: "path")
        }
        dict["claude_enabled"] = claudeEnabled

        // Metadata fields — omit when empty/nil.
        if !githubIssues.isEmpty {
            dict["github_issues"] = githubIssues.map { $0.absoluteString }
        } else {
            dict.removeValue(forKey: "github_issues")
        }
        if !githubPRs.isEmpty {
            dict["github_prs"] = githubPRs.map { $0.toDictionary() }
        } else {
            dict.removeValue(forKey: "github_prs")
        }
        if !links.isEmpty {
            dict["links"] = links.map { $0.toDictionary() }
        } else {
            dict.removeValue(forKey: "links")
        }
        if let openspecChange {
            dict["openspec_change"] = openspecChange
        } else {
            dict.removeValue(forKey: "openspec_change")
        }
        if let summary {
            dict["summary"] = summary
        } else {
            dict.removeValue(forKey: "summary")
        }

        return dict
    }

    public static func fromDictionary(_ dict: [String: Any]) -> Project? {
        guard let name = dict["name"] as? String,
              let space = dict["space"] as? Int
        else { return nil }
        let id = (dict["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        let path = dict["path"] as? String
        let claudeEnabled = (dict["claude_enabled"] as? Bool) ?? false

        let githubIssues: [URL] = (dict["github_issues"] as? [String])?.compactMap(URL.init(string:)) ?? []
        let githubPRs: [GitHubPREntry] = (dict["github_prs"] as? [[String: Any]])?.compactMap(GitHubPREntry.fromDictionary) ?? []
        let links: [LabeledLink] = (dict["links"] as? [[String: Any]])?.compactMap(LabeledLink.fromDictionary) ?? []
        let openspecChange = dict["openspec_change"] as? String
        let summary = dict["summary"] as? String

        var extras = dict
        for key in ["name", "space", "id", "path", "claude_enabled",
                     "github_issues", "github_prs", "links", "openspec_change", "summary"] {
            extras.removeValue(forKey: key)
        }
        return Project(
            id: id,
            name: name,
            space: space,
            path: path,
            claudeEnabled: claudeEnabled,
            extraFields: extras,
            githubIssues: githubIssues,
            githubPRs: githubPRs,
            links: links,
            openspecChange: openspecChange,
            summary: summary
        )
    }
}
