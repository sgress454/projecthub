import Combine
import Foundation

/// Holds the runtime state (color + working) for every project, keyed by
/// project id. Published so SwiftUI views and the menu builder can observe
/// changes and re-render.
///
/// Mutation is enforced to happen on the main queue so `@Published` doesn't
/// emit a "Publishing changes from background threads" warning. Call sites
/// that are already on main apply synchronously; anything else bounces.
public final class ProjectStateStore: ObservableObject {
    public static let shared = ProjectStateStore()

    @Published public private(set) var states: [UUID: ProjectRuntimeState] = [:]

    public init() {}

    public func state(for projectId: UUID) -> ProjectRuntimeState {
        states[projectId] ?? .idle
    }

    public func setState(_ newState: ProjectRuntimeState, for projectId: UUID) {
        runOnMain { self.states[projectId] = newState }
    }

    public func reset(projectId: UUID) {
        setState(.idle, for: projectId)
    }

    public func removeAll() {
        runOnMain { self.states.removeAll() }
    }

    public func removeState(for projectId: UUID) {
        runOnMain { self.states.removeValue(forKey: projectId) }
    }

    /// Convenience: count projects whose color is red or yellow. Driven
    /// entirely by `states`, so projects that have never received an event
    /// are treated as green (zero-contribution).
    public var badgeCount: Int {
        states.values.reduce(0) { acc, s in
            (s.status == .red || s.status == .yellow) ? acc + 1 : acc
        }
    }

    /// Whether any project is currently red. Used to pick the badge tint.
    public var hasAnyRed: Bool {
        states.values.contains(where: { $0.status == .red })
    }

    /// Whether any project is currently in the `working` sub-state.
    /// Drives the menu bar icon pulse animation.
    public var hasAnyWorking: Bool {
        states.values.contains(where: { $0.working })
    }

    private func runOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}
