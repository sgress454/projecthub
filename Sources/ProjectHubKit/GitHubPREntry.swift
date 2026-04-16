import Foundation

/// A GitHub PR URL stored on a project, tagged with whether it was
/// auto-discovered (by branch) or manually added by the user.
public struct GitHubPREntry: Equatable {
    public enum Source: String {
        case auto
        case manual
    }

    public var url: URL
    public var source: Source

    public init(url: URL, source: Source) {
        self.url = url
        self.source = source
    }

    public func toDictionary() -> [String: Any] {
        ["url": url.absoluteString, "source": source.rawValue]
    }

    public static func fromDictionary(_ dict: [String: Any]) -> GitHubPREntry? {
        guard let urlString = dict["url"] as? String,
              let url = URL(string: urlString),
              let sourceString = dict["source"] as? String,
              let source = Source(rawValue: sourceString)
        else { return nil }
        return GitHubPREntry(url: url, source: source)
    }
}
