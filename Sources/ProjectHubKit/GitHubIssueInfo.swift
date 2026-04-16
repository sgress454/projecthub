import Foundation

/// Cached metadata for a GitHub issue, populated by `GitHubSync`.
public struct GitHubIssueInfo {
    public let number: Int
    public let title: String
    public let url: URL
    /// One of "OPEN" or "CLOSED".
    public let state: String

    public init(number: Int, title: String, url: URL, state: String) {
        self.number = number
        self.title = title
        self.url = url
        self.state = state
    }
}
