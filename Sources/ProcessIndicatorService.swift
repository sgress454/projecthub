import Combine
import Foundation
import ProjectHubKit

/// Periodically scans local processes for Fleet server / webpack matches and
/// publishes a per-project indicator map. Subscribers (the menu renderer)
/// re-render whenever the map changes.
///
/// The scan runs on the main run loop on a 2-second cadence — cheap enough
/// (a few hundred sysctls + libproc calls) that we don't bother with a
/// background queue for v1.
final class ProcessIndicatorService: ObservableObject {
    static let shared = ProcessIndicatorService()

    @Published private(set) var indicators: [UUID: FleetProcessIndicators] = [:]

    private var timer: Timer?
    private var projectsObserver: AnyCancellable?

    private init() {}

    func start() {
        // Re-tick when the project list changes so a freshly-added project
        // can immediately claim the running process attributed to its path.
        projectsObserver = ProjectStore.shared.$projects
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.tick() }

        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        projectsObserver = nil
    }

    private func tick() {
        let snapshots = ProcessScanner.snapshot()
        let projects = ProjectStore.shared.projects
        let next = FleetProcessMatcher.attribute(snapshots: snapshots, projects: projects)
        if next != indicators {
            indicators = next
        }
    }
}
