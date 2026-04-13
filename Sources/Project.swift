import Foundation

struct Project: Identifiable, Equatable {
    let id: UUID
    var name: String
    var space: Int
    var extraFields: [String: Any]

    init(id: UUID = UUID(), name: String, space: Int, extraFields: [String: Any] = [:]) {
        self.id = id
        self.name = name
        self.space = space
        self.extraFields = extraFields
    }

    static func == (lhs: Project, rhs: Project) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.space == rhs.space
    }

    func toDictionary() -> [String: Any] {
        var dict = extraFields
        dict["name"] = name
        dict["space"] = space
        dict["id"] = id.uuidString
        return dict
    }

    static func fromDictionary(_ dict: [String: Any]) -> Project? {
        guard let name = dict["name"] as? String,
              let space = dict["space"] as? Int
        else { return nil }
        let id = (dict["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        var extras = dict
        extras.removeValue(forKey: "name")
        extras.removeValue(forKey: "space")
        extras.removeValue(forKey: "id")
        return Project(id: id, name: name, space: space, extraFields: extras)
    }
}
