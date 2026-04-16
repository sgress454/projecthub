import Foundation

/// Pure state-transition function. Takes the current runtime state, an
/// incoming hook event, and (optionally) the classifier result for Stop
/// events. Returns the new state. No side effects, no dependencies.
///
/// Invariants (see design D1 and spec `Per-project Claude state tracking`):
/// - `Notification`      → red, working=false
/// - `Stop` w/o classifier → color unchanged, working=false (awaiting async classifier)
/// - `Stop` w/ QUESTION   → red,    working=false
/// - `Stop` w/ REPORT     → yellow, working=false
/// - `Stop` w/ DONE       → green,  working=false
/// - `Stop` w/ FAILURE    → red,    working=false  (safe bias)
/// - `UserPromptSubmit`   → green, working=true
/// - `PreToolUse`         → green, working=true  (permission granted /
///                                                 tool about to run)
/// - `PostToolUse`        → green, working=true  (tool finished running)
public func transition(
    state: ProjectRuntimeState,
    event: HookEvent,
    classifier: ClassifierResult? = nil
) -> ProjectRuntimeState {
    switch event.kind {
    case .notification:
        return ProjectRuntimeState(status: .red, working: false)

    case .stop:
        // Stop always ends `working` immediately — Claude is no longer mid-turn.
        // Color updates only when a classifier result is supplied.
        guard let classifier else {
            return ProjectRuntimeState(status: state.status, working: false)
        }
        let newStatus: ProjectStatus
        switch classifier {
        case .question, .failure: newStatus = .red
        case .report: newStatus = .yellow
        case .done: newStatus = .green
        }
        return ProjectRuntimeState(status: newStatus, working: false)

    case .userPromptSubmit:
        return ProjectRuntimeState(status: .green, working: true)

    case .preToolUse, .postToolUse:
        // Claude is about to execute (PreToolUse) or just finished
        // executing (PostToolUse) a tool. Either way the user is no
        // longer blocking — the moment a PreToolUse fires after a
        // permission Notification, the red should clear to green with
        // the spinner. The spinner runs until Stop.
        return ProjectRuntimeState(status: .green, working: true)
    }
}

/// Active-space observation transition: when macOS becomes the project's
/// Space, downgrade red → yellow. Other states are unchanged.
public func transitionOnActiveSpaceBecome(
    _ state: ProjectRuntimeState
) -> ProjectRuntimeState {
    if state.status == .red {
        return ProjectRuntimeState(status: .yellow, working: state.working)
    }
    return state
}
