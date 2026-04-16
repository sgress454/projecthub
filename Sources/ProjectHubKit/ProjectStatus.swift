import Foundation

/// Color state shown per project in the menu and counted for the menu bar badge.
public enum ProjectStatus: String, CaseIterable, Codable {
    case green
    case yellow
    case red
}

/// Full per-project runtime state. `working` is a transient sub-state that
/// renders as a spinner in place of the `status` dot; it can co-exist with
/// any color (though in practice we only pair it with `.green` after a
/// `UserPromptSubmit`).
public struct ProjectRuntimeState: Equatable, Codable {
    public var status: ProjectStatus
    public var working: Bool

    public init(status: ProjectStatus = .green, working: Bool = false) {
        self.status = status
        self.working = working
    }

    /// The idle default — what a never-seen-before project starts at.
    public static let idle = ProjectRuntimeState(status: .green, working: false)
}

/// Three-way Stop classification (plus a `.failure` sentinel for times when
/// `claude -p` can't be reached / parsed — which maps to red in the transition).
public enum ClassifierResult: String, Codable {
    case question = "QUESTION"
    case report = "REPORT"
    case done = "DONE"
    case failure = "FAILURE"
}
