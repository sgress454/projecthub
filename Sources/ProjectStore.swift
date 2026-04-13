import Combine
import Foundation

final class ProjectStore: ObservableObject {
    static let shared = ProjectStore()

    @Published private(set) var projects: [Project] = []

    private let fileURL: URL
    private let schemaVersion = 1
    private var extraTopLevelFields: [String: Any] = [:]
    private var saveWorkItem: DispatchWorkItem?

    private init() {
        let fm = FileManager.default
        let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = (appSupport ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support"))
            .appendingPathComponent("ProjectHub", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("projects.json")
        load()
    }

    // MARK: - Public API

    func add(name: String = "New Project", space: Int) {
        let project = Project(name: name, space: space)
        projects.append(project)
        scheduleSave()
    }

    func remove(id: UUID) {
        projects.removeAll { $0.id == id }
        scheduleSave()
    }

    func update(id: UUID, name: String? = nil, space: Int? = nil) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        if let name { projects[idx].name = name }
        if let space { projects[idx].space = space }
        scheduleSave()
    }

    func nextAvailableSpace() -> Int {
        let used = Set(projects.map { $0.space })
        for n in 1 ... 9 where !used.contains(n) { return n }
        return 1
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            // First-launch: nothing to load
            return
        }
        let projectsArr = raw["projects"] as? [[String: Any]] ?? []
        self.projects = projectsArr.compactMap(Project.fromDictionary)
        // Preserve any unknown top-level fields (future versions)
        var extras = raw
        extras.removeValue(forKey: "projects")
        extras.removeValue(forKey: "version")
        self.extraTopLevelFields = extras
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func save() {
        var payload: [String: Any] = extraTopLevelFields
        payload["version"] = schemaVersion
        payload["projects"] = projects.map { $0.toDictionary() }
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
