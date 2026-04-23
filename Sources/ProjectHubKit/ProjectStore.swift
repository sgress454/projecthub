import Combine
import Foundation

/// Global settings persisted alongside the project list. Currently tracks
/// whether ProjectHub has installed its Claude Code hook into the user's
/// `~/.claude/settings.json`. Extra/unknown fields are round-tripped.
public struct Settings: Equatable {
    public var claudeHookInstalled: Bool
    public var extraFields: [String: Any]

    public init(claudeHookInstalled: Bool = false, extraFields: [String: Any] = [:]) {
        self.claudeHookInstalled = claudeHookInstalled
        self.extraFields = extraFields
    }

    public static func == (lhs: Settings, rhs: Settings) -> Bool {
        lhs.claudeHookInstalled == rhs.claudeHookInstalled
    }

    public func toDictionary() -> [String: Any] {
        var dict = extraFields
        dict["claude_hook_installed"] = claudeHookInstalled
        return dict
    }

    public static func fromDictionary(_ dict: [String: Any]) -> Settings {
        var extras = dict
        extras.removeValue(forKey: "claude_hook_installed")
        return Settings(
            claudeHookInstalled: (dict["claude_hook_installed"] as? Bool) ?? false,
            extraFields: extras
        )
    }
}

public final class ProjectStore: ObservableObject {
    public static let shared = ProjectStore()

    @Published public private(set) var projects: [Project] = []
    @Published public private(set) var settings: Settings = Settings()

    /// Current on-disk schema version written by this binary.
    /// v1 files (name + space only) still load correctly — the extra fields
    /// simply take their defaults.
    internal static let currentSchemaVersion = 3

    private let fileURL: URL
    private var extraTopLevelFields: [String: Any] = [:]
    private var saveWorkItem: DispatchWorkItem?
    private let saveQueue: DispatchQueue

    // Production singleton initializer — writes to ~/Library/Application Support.
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
        self.saveQueue = DispatchQueue.main
        load()
    }

    // Test-only initializer that targets a specific file and runs saves
    // synchronously so round-trip tests don't need to wait for a debounce.
    internal init(fileURL: URL, synchronous: Bool = true) {
        self.fileURL = fileURL
        self.saveQueue = synchronous ? DispatchQueue(label: "ProjectStore.test", qos: .userInitiated) : DispatchQueue.main
        load()
    }

    // MARK: - Public API

    public func add(name: String = "New Project", space: Int) {
        let project = Project(name: name, space: space)
        projects.append(project)
        scheduleSave()
    }

    public func remove(id: UUID) {
        projects.removeAll { $0.id == id }
        scheduleSave()
    }

    public func update(id: UUID, name: String? = nil, space: Int? = nil) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        if let name { projects[idx].name = name }
        if let space { projects[idx].space = space }
        scheduleSave()
    }

    /// Sets (or clears, with nil) the filesystem path for a project.
    /// Also runs OpenSpec auto-detection if no change is manually set.
    public func setPath(id: UUID, path: String?) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[idx].path = path
        // Auto-detect OpenSpec change when path changes, unless manually set.
        if let path, projects[idx].openspecChange == nil {
            projects[idx].openspecChange = OpenSpecDetector.detectChange(at: path)
        }
        scheduleSave()
    }

    /// Sets the per-project Claude monitoring opt-in.
    public func setClaudeEnabled(id: UUID, enabled: Bool) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[idx].claudeEnabled = enabled
        scheduleSave()
    }

    /// Updates the global "hook installed" flag.
    public func setClaudeHookInstalled(_ installed: Bool) {
        settings.claudeHookInstalled = installed
        scheduleSave()
    }

    // MARK: - Metadata API (v3)

    public func setGithubIssues(id: UUID, issues: [URL]) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[idx].githubIssues = issues
        scheduleSave()
    }

    public func setGithubPRs(id: UUID, prs: [GitHubPREntry]) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[idx].githubPRs = prs
        scheduleSave()
    }

    public func setLinks(id: UUID, links: [LabeledLink]) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[idx].links = links
        scheduleSave()
    }

    public func setOpenspecChange(id: UUID, change: String?) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[idx].openspecChange = change
        scheduleSave()
    }

    public func setSummary(id: UUID, summary: String?) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[idx].summary = summary
        scheduleSave()
    }

    public func nextAvailableSpace() -> Int {
        let used = Set(projects.map { $0.space })
        for n in 1 ... 16 where !used.contains(n) { return n }
        return 1
    }

    /// Forces any pending debounced save to flush immediately. Useful for tests
    /// and for shutdown paths where the runloop will not run another iteration.
    public func flushPendingSave() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        save()
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

        if let settingsDict = raw["settings"] as? [String: Any] {
            self.settings = Settings.fromDictionary(settingsDict)
        }

        // Preserve any unknown top-level fields (for forward compatibility).
        var extras = raw
        extras.removeValue(forKey: "projects")
        extras.removeValue(forKey: "settings")
        extras.removeValue(forKey: "version")
        self.extraTopLevelFields = extras

        // Auto-detect OpenSpec changes for projects that have paths but no manual setting.
        for i in projects.indices {
            if let path = projects[i].path, projects[i].openspecChange == nil {
                projects[i].openspecChange = OpenSpecDetector.detectChange(at: path)
            }
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = item
        saveQueue.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func save() {
        var payload: [String: Any] = extraTopLevelFields
        payload["version"] = Self.currentSchemaVersion
        payload["projects"] = projects.map { $0.toDictionary() }
        payload["settings"] = settings.toDictionary()
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
