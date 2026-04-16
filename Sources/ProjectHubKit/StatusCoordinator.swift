import Combine
import Foundation

/// Wires together the event log watcher, the classifier, the state store,
/// and the project list. Owns the monitoring lifecycle.
///
/// Lifecycle:
///   let coord = StatusCoordinator(...)
///   coord.start()              // replay + begin tailing events.jsonl
///   coord.activeSpaceBecame(N) // drive red→yellow from the app delegate
///   coord.stop()               // on quit (optional)
public final class StatusCoordinator {
    public static let shared = StatusCoordinator()

    private let projectStore: ProjectStore
    private let stateStore: ProjectStateStore
    private let classifier: Classifier
    private var watcher: EventLogWatcher?
    private var cancellables = Set<AnyCancellable>()

    /// Snapshot of claudeEnabled per project from the last `handleProjectsChanged` tick.
    /// Used to detect flips so we can reset stale state (tasks 6.4 / 6.5).
    private var previousClaudeEnabled: [UUID: Bool] = [:]

    public init(
        projectStore: ProjectStore = .shared,
        stateStore: ProjectStateStore = .shared,
        classifier: Classifier = .shared
    ) {
        self.projectStore = projectStore
        self.stateStore = stateStore
        self.classifier = classifier
    }

    // MARK: - Lifecycle

    public func start(logURL: URL = EventLog.logURL) {
        observeProjectChanges()

        let watcher = EventLogWatcher(
            fileURL: logURL,
            queue: .main
        ) { [weak self] event in
            self?.handleEvent(event)
        }
        self.watcher = watcher
        watcher.startWithReplay()
    }

    public func stop() {
        watcher?.stop()
        watcher = nil
        cancellables.removeAll()
    }

    // MARK: - External triggers

    /// Called when macOS reports the active Space changed. Downgrades any
    /// project assigned to the new active Space from red to yellow.
    public func activeSpaceBecame(_ spaceNumber: Int) {
        for project in projectStore.projects where project.space == spaceNumber {
            let current = stateStore.state(for: project.id)
            let next = transitionOnActiveSpaceBecome(current)
            if next != current {
                stateStore.setState(next, for: project.id)
            }
        }
    }

    /// User action: "I've seen it, clear the attention state." Clears red
    /// OR yellow to green. No-op on green.
    ///
    /// Red was initially not dismissible (Claude is genuinely waiting), but
    /// real use surfaced the case where red fires while the user is already
    /// in the project's Space — the active-Space downgrade only fires on
    /// Space change, not on steady-state presence, so red otherwise persists
    /// until the user switches away and back. Dismiss remains explicit (a
    /// per-row × button, distinct from the click-to-switch row action), so
    /// it can't be invoked accidentally.
    public func dismiss(projectId: UUID) {
        let current = stateStore.state(for: projectId)
        guard current.status == .red || current.status == .yellow else { return }
        stateStore.setState(.idle, for: projectId)
    }

    // MARK: - Event handling

    /// Applied to every parsed event from the log. `internal` so tests can
    /// drive the coordinator without setting up a real watcher.
    internal func handleEvent(_ event: HookEvent) {
        guard let project = matchProject(cwd: event.cwd, in: projectStore.projects) else {
            return
        }
        guard project.claudeEnabled else { return }

        let current = stateStore.state(for: project.id)
        let immediate = transition(state: current, event: event)
        if immediate != current {
            stateStore.setState(immediate, for: project.id)
        }

        // For Stop events, also run the async classifier; the final state is
        // applied when it resolves (or .failure defaults to red).
        guard event.kind == .stop, let transcriptPath = event.transcriptPath else { return }

        let projectId = project.id
        Task { [weak self] in
            guard let self else { return }
            let result = await self.classifier.classify(transcriptPath: transcriptPath)

            // Re-check enablement at apply time: the user may have flipped
            // claudeEnabled off while we were waiting for the classifier.
            let stillEnabled = self.projectStore.projects
                .first(where: { $0.id == projectId })?
                .claudeEnabled == true
            guard stillEnabled else { return }

            let now = self.stateStore.state(for: projectId)
            let final = transition(state: now, event: event, classifier: result)
            self.stateStore.setState(final, for: projectId)

            if result == .failure {
                NSLog("ProjectHub: classifier returned .failure for project \(projectId), defaulting to red")
            }
        }
    }

    // MARK: - Project-list observation

    private func observeProjectChanges() {
        projectStore.$projects
            .sink { [weak self] projects in
                self?.handleProjectsChanged(projects)
            }
            .store(in: &cancellables)
    }

    internal func handleProjectsChanged(_ projects: [Project]) {
        let currentEnabled = Dictionary(
            uniqueKeysWithValues: projects.map { ($0.id, $0.claudeEnabled) }
        )

        // Detect flips in either direction — both reset state to green per
        // tasks 6.4 and 6.5 (force-green means the same thing: drop state).
        for project in projects {
            guard let was = previousClaudeEnabled[project.id] else { continue }
            if was != project.claudeEnabled {
                stateStore.reset(projectId: project.id)
            }
        }

        // Drop state for projects the user deleted.
        let currentIds = Set(projects.map { $0.id })
        for id in previousClaudeEnabled.keys where !currentIds.contains(id) {
            stateStore.removeState(for: id)
        }

        previousClaudeEnabled = currentEnabled
    }
}
