import Foundation

/// Cached metadata for a GitHub PR, populated by `GitHubSync`.
public struct GitHubPRInfo {
    public let number: Int
    public let title: String
    public let url: URL
    /// One of "OPEN", "MERGED", "CLOSED".
    public let state: String
    public let isDraft: Bool
    /// One of "APPROVED", "CHANGES_REQUESTED", "REVIEW_REQUIRED", or empty.
    public let reviewDecision: String
    /// Whether one or more users are assigned to the PR.
    public let hasAssignees: Bool
    /// Count of unresolved review comments not authored by the PR author.
    public let unresolvedCommentCount: Int

    public init(
        number: Int, title: String, url: URL, state: String,
        isDraft: Bool = false, reviewDecision: String = "",
        hasAssignees: Bool = false, unresolvedCommentCount: Int = 0
    ) {
        self.number = number
        self.title = title
        self.url = url
        self.state = state
        self.isDraft = isDraft
        self.reviewDecision = reviewDecision
        self.hasAssignees = hasAssignees
        self.unresolvedCommentCount = unresolvedCommentCount
    }

    /// Human-readable display state combining state, draft, and review decision.
    public var displayState: String {
        if state == "MERGED" { return "merged" }
        if state == "CLOSED" { return "closed" }
        if isDraft { return "draft" }
        switch reviewDecision {
        case "APPROVED": return "approved"
        case "CHANGES_REQUESTED": return "changes requested"
        default: return "open"
        }
    }
}
