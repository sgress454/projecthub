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

    public init(
        id: UUID = UUID(),
        name: String,
        space: Int,
        path: String? = nil,
        claudeEnabled: Bool = false,
        extraFields: [String: Any] = [:]
    ) {
        self.id = id
        self.name = name
        self.space = space
        self.path = path
        self.claudeEnabled = claudeEnabled
        self.extraFields = extraFields
    }

    public static func == (lhs: Project, rhs: Project) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.space == rhs.space
            && lhs.path == rhs.path
            && lhs.claudeEnabled == rhs.claudeEnabled
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
        return dict
    }

    public static func fromDictionary(_ dict: [String: Any]) -> Project? {
        guard let name = dict["name"] as? String,
              let space = dict["space"] as? Int
        else { return nil }
        let id = (dict["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        let path = dict["path"] as? String
        let claudeEnabled = (dict["claude_enabled"] as? Bool) ?? false
        var extras = dict
        extras.removeValue(forKey: "name")
        extras.removeValue(forKey: "space")
        extras.removeValue(forKey: "id")
        extras.removeValue(forKey: "path")
        extras.removeValue(forKey: "claude_enabled")
        return Project(
            id: id,
            name: name,
            space: space,
            path: path,
            claudeEnabled: claudeEnabled,
            extraFields: extras
        )
    }
}
