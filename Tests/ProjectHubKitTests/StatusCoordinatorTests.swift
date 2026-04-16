import Foundation
import XCTest
@testable import ProjectHubKit

final class StatusCoordinatorTests: XCTestCase {
    private var tempDir: URL!
    private var store: ProjectStore!
    private var stateStore: ProjectStateStore!
    private var classifier: Classifier!
    private var coordinator: StatusCoordinator!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ProjectHubCoordTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        store = ProjectStore(fileURL: tempDir.appendingPathComponent("projects.json"))
        stateStore = ProjectStateStore()
        classifier = Classifier()
        coordinator = StatusCoordinator(
            projectStore: store,
            stateStore: stateStore,
            classifier: classifier
        )
    }

    override func tearDownWithError() throws {
        coordinator.stop()
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func event(_ kind: HookEvent.Kind, cwd: String, transcriptPath: String? = nil) -> HookEvent {
        HookEvent(kind: kind, cwd: cwd, transcriptPath: transcriptPath)
    }

    // MARK: - Event routing

    func testNotificationRoutesToMatchedEnabledProject() throws {
        store.add(name: "p", space: 1)
        let id = store.projects[0].id
        store.setPath(id: id, path: "/tmp/proj")
        store.setClaudeEnabled(id: id, enabled: true)

        coordinator.handleEvent(event(.notification, cwd: "/tmp/proj/src"))
        XCTAssertEqual(stateStore.state(for: id).status, .red)
    }

    func testEventForDisabledProjectHasNoEffect() {
        store.add(name: "p", space: 1)
        let id = store.projects[0].id
        store.setPath(id: id, path: "/tmp/proj")
        // claudeEnabled stays false

        coordinator.handleEvent(event(.notification, cwd: "/tmp/proj/src"))
        XCTAssertEqual(stateStore.state(for: id), .idle)
    }

    func testEventWithoutPathProjectMatchIgnored() {
        store.add(name: "p", space: 1)
        let id = store.projects[0].id
        // no path set, claudeEnabled would be ineffective anyway
        store.setClaudeEnabled(id: id, enabled: true)

        coordinator.handleEvent(event(.notification, cwd: "/tmp/elsewhere"))
        XCTAssertEqual(stateStore.state(for: id), .idle)
    }

    func testUserPromptSubmitStartsWorking() {
        store.add(name: "p", space: 1)
        let id = store.projects[0].id
        store.setPath(id: id, path: "/tmp/proj")
        store.setClaudeEnabled(id: id, enabled: true)
        stateStore.setState(.init(status: .red), for: id)

        coordinator.handleEvent(event(.userPromptSubmit, cwd: "/tmp/proj"))
        XCTAssertEqual(stateStore.state(for: id), .init(status: .green, working: true))
    }

    func testPostToolUseClearsAttentionStateToGreenWorking() {
        // Claude is doing tool work on the user's behalf → not blocking.
        store.add(name: "p", space: 1)
        let id = store.projects[0].id
        store.setPath(id: id, path: "/tmp/proj")
        store.setClaudeEnabled(id: id, enabled: true)
        stateStore.setState(.init(status: .yellow, working: false), for: id)

        coordinator.handleEvent(event(.postToolUse, cwd: "/tmp/proj"))
        XCTAssertEqual(stateStore.state(for: id), .init(status: .green, working: true))
    }

    // MARK: - Dismiss

    func testDismissYellowClearsToGreen() {
        store.add(name: "p", space: 1)
        let id = store.projects[0].id
        stateStore.setState(.init(status: .yellow, working: false), for: id)

        coordinator.dismiss(projectId: id)
        XCTAssertEqual(stateStore.state(for: id), .idle)
    }

    func testDismissRedClearsToGreen() {
        // Red can fire while the user is already in the Space (Notification
        // or Stop+QUESTION with no Space change), at which point dismiss
        // is the only non-detour path to green.
        store.add(name: "p", space: 1)
        let id = store.projects[0].id
        stateStore.setState(.init(status: .red, working: false), for: id)

        coordinator.dismiss(projectId: id)
        XCTAssertEqual(stateStore.state(for: id), .idle)
    }

    func testDismissGreenIsIdempotent() {
        store.add(name: "p", space: 1)
        let id = store.projects[0].id
        stateStore.setState(.init(status: .green, working: true), for: id)

        coordinator.dismiss(projectId: id)
        XCTAssertEqual(stateStore.state(for: id), .init(status: .green, working: true))
    }

    // MARK: - Active space

    func testActiveSpaceBecomeDowngradesRed() {
        store.add(name: "p", space: 3)
        let id = store.projects[0].id
        stateStore.setState(.init(status: .red), for: id)

        coordinator.activeSpaceBecame(3)
        XCTAssertEqual(stateStore.state(for: id).status, .yellow)
    }

    func testActiveSpaceBecomeLeavesYellowAlone() {
        store.add(name: "p", space: 3)
        let id = store.projects[0].id
        stateStore.setState(.init(status: .yellow), for: id)

        coordinator.activeSpaceBecame(3)
        XCTAssertEqual(stateStore.state(for: id).status, .yellow)
    }

    // MARK: - claudeEnabled flips (tasks 6.4, 6.5)

    func testFlipOffResetsStateToGreen() {
        store.add(name: "p", space: 1)
        let id = store.projects[0].id
        store.setPath(id: id, path: "/tmp/proj")
        store.setClaudeEnabled(id: id, enabled: true)
        // prime the coordinator's snapshot
        coordinator.handleProjectsChanged(store.projects)

        // project goes red
        stateStore.setState(.init(status: .red), for: id)

        // user flips claudeEnabled off
        store.setClaudeEnabled(id: id, enabled: false)
        coordinator.handleProjectsChanged(store.projects)

        XCTAssertEqual(stateStore.state(for: id), .idle)
    }

    func testFlipOnResetsAnyCarryoverState() {
        store.add(name: "p", space: 1)
        let id = store.projects[0].id
        store.setPath(id: id, path: "/tmp/proj")
        // claudeEnabled = false initially
        coordinator.handleProjectsChanged(store.projects)

        // Somehow state got muddied (shouldn't happen, but guard the invariant)
        stateStore.setState(.init(status: .yellow), for: id)

        store.setClaudeEnabled(id: id, enabled: true)
        coordinator.handleProjectsChanged(store.projects)

        XCTAssertEqual(stateStore.state(for: id), .idle)
    }

    func testProjectRemovalDropsState() {
        store.add(name: "p", space: 1)
        let id = store.projects[0].id
        coordinator.handleProjectsChanged(store.projects)
        stateStore.setState(.init(status: .red), for: id)

        store.remove(id: id)
        coordinator.handleProjectsChanged(store.projects)
        XCTAssertNil(stateStore.states[id])
    }

    // MARK: - Stop + classifier (integration)

    func testStopWithoutTranscriptStillEndsWorking() {
        store.add(name: "p", space: 1)
        let id = store.projects[0].id
        store.setPath(id: id, path: "/tmp/proj")
        store.setClaudeEnabled(id: id, enabled: true)
        stateStore.setState(.init(status: .yellow, working: true), for: id)

        coordinator.handleEvent(event(.stop, cwd: "/tmp/proj"))  // no transcript
        // working ends immediately; no classifier task runs.
        XCTAssertEqual(stateStore.state(for: id), .init(status: .yellow, working: false))
    }
}
