import XCTest
@testable import ProjectHubKit

final class StateTransitionTests: XCTestCase {
    private let cwd = "/Users/scott/Development/proj"

    private func event(_ kind: HookEvent.Kind) -> HookEvent {
        HookEvent(kind: kind, cwd: cwd)
    }

    // MARK: - Notification

    func testNotificationSetsRed() {
        let before = ProjectRuntimeState(status: .green, working: true)
        let after = transition(state: before, event: event(.notification))
        XCTAssertEqual(after.status, .red)
        XCTAssertFalse(after.working, "Notification means Claude is blocked; working ends")
    }

    func testNotificationFromYellowStillSetsRed() {
        let before = ProjectRuntimeState(status: .yellow)
        let after = transition(state: before, event: event(.notification))
        XCTAssertEqual(after.status, .red)
    }

    // MARK: - Stop × 3 classifications + failure + no-classifier

    func testStopWithQuestionSetsRed() {
        let after = transition(state: .init(status: .green), event: event(.stop), classifier: .question)
        XCTAssertEqual(after, .init(status: .red, working: false))
    }

    func testStopWithReportSetsYellow() {
        let after = transition(state: .init(status: .green), event: event(.stop), classifier: .report)
        XCTAssertEqual(after, .init(status: .yellow, working: false))
    }

    func testStopWithDoneSetsGreen() {
        let after = transition(state: .init(status: .red), event: event(.stop), classifier: .done)
        XCTAssertEqual(after, .init(status: .green, working: false))
    }

    func testStopWithFailureDefaultsToRed() {
        let after = transition(state: .init(status: .green), event: event(.stop), classifier: .failure)
        XCTAssertEqual(after, .init(status: .red, working: false))
    }

    func testStopWithoutClassifierPreservesColorAndEndsWorking() {
        let before = ProjectRuntimeState(status: .yellow, working: true)
        let after = transition(state: before, event: event(.stop))
        XCTAssertEqual(after.status, .yellow, "color unchanged until classifier returns")
        XCTAssertFalse(after.working, "working always ends immediately on Stop")
    }

    // MARK: - UserPromptSubmit

    func testUserPromptSubmitClearsToGreenAndStartsWorking() {
        let before = ProjectRuntimeState(status: .red)
        let after = transition(state: before, event: event(.userPromptSubmit))
        XCTAssertEqual(after, .init(status: .green, working: true))
    }

    func testUserPromptSubmitFromYellowAlsoGreenWorking() {
        let after = transition(
            state: .init(status: .yellow, working: false),
            event: event(.userPromptSubmit)
        )
        XCTAssertEqual(after, .init(status: .green, working: true))
    }

    // MARK: - Pre/PostToolUse both clear to green + working

    func testPreToolUseClearsToGreenWorking() {
        // Key case: a permission prompt set state to red. The user approves.
        // PreToolUse fires with the permission granted and the tool about
        // to execute — state should clear immediately without waiting for
        // the tool to finish.
        let afterApproval = transition(state: .init(status: .red), event: event(.preToolUse))
        XCTAssertEqual(afterApproval, .init(status: .green, working: true))

        let fromYellow = transition(state: .init(status: .yellow), event: event(.preToolUse))
        XCTAssertEqual(fromYellow, .init(status: .green, working: true))
    }

    func testPostToolUseClearsToGreenWorking() {
        let fromYellow = transition(state: .init(status: .yellow, working: false), event: event(.postToolUse))
        XCTAssertEqual(fromYellow, .init(status: .green, working: true))

        let fromRed = transition(state: .init(status: .red, working: false), event: event(.postToolUse))
        XCTAssertEqual(fromRed, .init(status: .green, working: true))

        let fromGreen = transition(state: .init(status: .green, working: true), event: event(.postToolUse))
        XCTAssertEqual(fromGreen, .init(status: .green, working: true))
    }

    // MARK: - Active-Space becomes this

    func testActiveSpaceBecomeDowngradesRedToYellow() {
        let after = transitionOnActiveSpaceBecome(.init(status: .red))
        XCTAssertEqual(after.status, .yellow)
    }

    func testActiveSpaceBecomeLeavesYellowUnchanged() {
        let before = ProjectRuntimeState(status: .yellow, working: false)
        let after = transitionOnActiveSpaceBecome(before)
        XCTAssertEqual(after, before)
    }

    func testActiveSpaceBecomeLeavesGreenUnchanged() {
        let before = ProjectRuntimeState(status: .green, working: true)
        let after = transitionOnActiveSpaceBecome(before)
        XCTAssertEqual(after, before)
    }

    func testActiveSpaceBecomePreservesWorkingWhenDowngrading() {
        let after = transitionOnActiveSpaceBecome(.init(status: .red, working: true))
        XCTAssertEqual(after, .init(status: .yellow, working: true))
    }
}

final class ProjectStateStoreTests: XCTestCase {
    func testSetAndRead() {
        let store = ProjectStateStore()
        let id = UUID()
        XCTAssertEqual(store.state(for: id), .idle)
        store.setState(.init(status: .red), for: id)
        XCTAssertEqual(store.state(for: id), .init(status: .red))
    }

    func testBadgeCountCountsRedAndYellow() {
        let store = ProjectStateStore()
        store.setState(.init(status: .red), for: UUID())
        store.setState(.init(status: .yellow), for: UUID())
        store.setState(.init(status: .green), for: UUID())
        store.setState(.init(status: .red), for: UUID())
        XCTAssertEqual(store.badgeCount, 3)
        XCTAssertTrue(store.hasAnyRed)
    }

    func testBadgeCountIgnoresWorkingOnGreen() {
        let store = ProjectStateStore()
        store.setState(.init(status: .green, working: true), for: UUID())
        XCTAssertEqual(store.badgeCount, 0)
        XCTAssertFalse(store.hasAnyRed)
    }

    func testResetAndRemove() {
        let store = ProjectStateStore()
        let id = UUID()
        store.setState(.init(status: .red), for: id)
        store.reset(projectId: id)
        XCTAssertEqual(store.state(for: id), .idle)

        store.setState(.init(status: .red), for: id)
        store.removeState(for: id)
        XCTAssertNil(store.states[id])
    }
}
