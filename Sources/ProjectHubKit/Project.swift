import Foundation

public struct Project: Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var space: Int
    /// Stable CoreGraphics Space identifier corresponding to `space`. Cached
    /// when the user assigns a Space; re-derived to renumber `space` when
    /// macOS Spaces are added, removed, or reordered. Nil for projects that
    /// haven't been reconciled yet (lazy capture populates on first run).
    public var spaceID64: UInt64?
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

    // MARK: - Archive fields (v4)

    /// When true, the project is set aside: hidden from the menu bar, shown
    /// only in the Archived section of Edit Projects, and excluded from all
    /// Space-related code paths. Combined with `space = 0` and `spaceID64 = nil`
    /// to express the "no positional assignment" shape.
    public var archived: Bool
    /// Moment the project was archived (ISO8601 on disk). Used to order the
    /// Archived section last-archived-first. Cleared by `restore()`.
    public var archivedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        space: Int,
        spaceID64: UInt64? = nil,
        path: String? = nil,
        claudeEnabled: Bool = false,
        extraFields: [String: Any] = [:],
        githubIssues: [URL] = [],
        githubPRs: [GitHubPREntry] = [],
        links: [LabeledLink] = [],
        openspecChange: String? = nil,
        summary: String? = nil,
        archived: Bool = false,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.space = space
        self.spaceID64 = spaceID64
        self.path = path
        self.claudeEnabled = claudeEnabled
        self.extraFields = extraFields
        self.githubIssues = githubIssues
        self.githubPRs = githubPRs
        self.links = links
        self.openspecChange = openspecChange
        self.summary = summary
        self.archived = archived
        self.archivedAt = archivedAt
    }

    public static func == (lhs: Project, rhs: Project) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.space == rhs.space
            && lhs.spaceID64 == rhs.spaceID64
            && lhs.path == rhs.path
            && lhs.claudeEnabled == rhs.claudeEnabled
            && lhs.githubIssues == rhs.githubIssues
            && lhs.githubPRs == rhs.githubPRs
            && lhs.links == rhs.links
            && lhs.openspecChange == rhs.openspecChange
            && lhs.summary == rhs.summary
            && lhs.archived == rhs.archived
            && lhs.archivedAt == rhs.archivedAt
    }

    /// Returns a copy in the archived shape: hidden from the menu bar,
    /// excluded from all Space-related code paths, identity and metadata
    /// preserved. `space = 0` is the "no positional assignment" sentinel —
    /// it falls below the 1..16 range used everywhere else, so reconcile/
    /// switch/highlight code naturally skips it.
    public func archive(now: Date = Date()) -> Project {
        var copy = self
        copy.archived = true
        copy.archivedAt = now
        copy.space = 0
        copy.spaceID64 = nil
        copy.path = nil
        copy.claudeEnabled = false
        return copy
    }

    /// Returns a copy with the archive state cleared. The project re-enters
    /// the unassigned-active state (`space = 0`, `spaceID64 = nil` from the
    /// prior archive); the user picks a Space from the row's Space picker.
    public func restore() -> Project {
        var copy = self
        copy.archived = false
        copy.archivedAt = nil
        return copy
    }

    public func toDictionary() -> [String: Any] {
        var dict = extraFields
        dict["name"] = name
        dict["space"] = space
        dict["id"] = id.uuidString
        if let spaceID64 {
            dict["space_id64"] = NSNumber(value: spaceID64)
        } else {
            dict.removeValue(forKey: "space_id64")
        }
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

        // Archive fields — omit when default (matches omit-when-empty pattern).
        if archived {
            dict["archived"] = true
        } else {
            dict.removeValue(forKey: "archived")
        }
        if let archivedAt {
            dict["archived_at"] = Self.archivedAtFormatter.string(from: archivedAt)
        } else {
            dict.removeValue(forKey: "archived_at")
        }

        return dict
    }

    public static func fromDictionary(_ dict: [String: Any]) -> Project? {
        guard let name = dict["name"] as? String,
              let space = dict["space"] as? Int
        else { return nil }
        let id = (dict["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        let spaceID64 = (dict["space_id64"] as? NSNumber)?.uint64Value
        let path = dict["path"] as? String
        let claudeEnabled = (dict["claude_enabled"] as? Bool) ?? false

        let githubIssues: [URL] = (dict["github_issues"] as? [String])?.compactMap(URL.init(string:)) ?? []
        let githubPRs: [GitHubPREntry] = (dict["github_prs"] as? [[String: Any]])?.compactMap(GitHubPREntry.fromDictionary) ?? []
        let links: [LabeledLink] = (dict["links"] as? [[String: Any]])?.compactMap(LabeledLink.fromDictionary) ?? []
        let openspecChange = dict["openspec_change"] as? String
        let summary = dict["summary"] as? String

        let archived = (dict["archived"] as? Bool) ?? false
        let archivedAt = (dict["archived_at"] as? String).flatMap(Self.archivedAtFormatter.date(from:))

        var extras = dict
        for key in ["name", "space", "id", "space_id64", "path", "claude_enabled",
                     "github_issues", "github_prs", "links", "openspec_change", "summary",
                     "archived", "archived_at"] {
            extras.removeValue(forKey: key)
        }
        return Project(
            id: id,
            name: name,
            space: space,
            spaceID64: spaceID64,
            path: path,
            claudeEnabled: claudeEnabled,
            extraFields: extras,
            githubIssues: githubIssues,
            githubPRs: githubPRs,
            links: links,
            openspecChange: openspecChange,
            summary: summary,
            archived: archived,
            archivedAt: archivedAt
        )
    }

    /// ISO8601 with timezone offset and fractional seconds — durable across
    /// timezones and stable enough to preserve archive ordering.
    private static let archivedAtFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
