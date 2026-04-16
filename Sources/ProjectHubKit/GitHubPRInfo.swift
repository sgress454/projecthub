import Foundation

/// Cached metadata for a GitHub PR, populated by `GitHubSync`.
public struct GitHubPRInfo {
    public let number: Int
    public let title: String
    public let url: URL
    /// One of "OPEN", "MERGED", "CLOSED".
    public let state: String
    /// Count of unresolved review comments not authored by the PR author.
    public let unresolvedCommentCount: Int

    public init(number: Int, title: String, url: URL, state: String, unresolvedCommentCount: Int) {
        self.number = number
        self.title = title
        self.url = url
        self.state = state
        self.unresolvedCommentCount = unresolvedCommentCount
    }
}
