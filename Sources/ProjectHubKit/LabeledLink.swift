import Foundation

public struct LabeledLink: Equatable {
    public var url: URL
    public var label: String

    public init(url: URL, label: String) {
        self.url = url
        self.label = label
    }

    public func toDictionary() -> [String: Any] {
        ["url": url.absoluteString, "label": label]
    }

    public static func fromDictionary(_ dict: [String: Any]) -> LabeledLink? {
        guard let urlString = dict["url"] as? String,
              let url = URL(string: urlString),
              let label = dict["label"] as? String
        else { return nil }
        return LabeledLink(url: url, label: label)
    }
}
