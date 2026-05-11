## Context

Once `stable-space-tracking` lands, projecthub knows each project's Space by a stable id64 and auto-renumbers projects when Spaces are added, removed, or reordered. That makes "close project" a primarily *windowing* problem: enumerate windows on a given Space, close them politely, and let the user finish the job in Mission Control.

The user's stated shape:
- "Done forever" semantics with optional archive (not a hibernate flow).
- Skip windows pinned to all desktops.
- Trust macOS to ask about unsaved work; offer a shutdown-style cancel/timeout.
- Don't programmatically remove the Space — the user closes it manually, projecthub picks up the change.
- Refuse to close projects on fullscreen-app Spaces; ask the user to exit fullscreen first.

## Goals / Non-Goals

**Goals:**
- One-click close that handles the windowing, the project record, and the renumber side-effect end-to-end.
- Honor unsaved-work dialogs by using each app's normal close path (red traffic light / Cmd+W).
- Archive option that preserves enough of the project for the user to remember it later (name, links, issues, PRs, openspec change, summary) without holding onto the Space-related fields.
- Refuse cleanly on edge cases (fullscreen Space, missing Accessibility) instead of half-completing.

**Non-Goals:**
- Programmatic Space removal.
- Closing apps entirely (windows only).
- Closing windows pinned to all desktops.
- Per-app close-behavior heuristics. AX → Cmd+W is the universal path.
- Multi-display awareness beyond what `stable-space-tracking` already provides.
- Restore flow that reopens windows (archive is metadata-only).

## Decisions

### Decision: AX `AXCloseButton.performAction` is the primary close path, Cmd+W is the fallback

For each target window, look up its AX element, query `AXCloseButton`, and call `AXUIElementPerformAction(closeButton, kAXPressAction)`. This is exactly what clicking the red traffic light does — apps respond with their normal "save changes?" sheet for dirty buffers. If AX returns no close button (some windows expose no close affordance) or the call fails, fall back to focusing the window and posting `Cmd+W` via `CGEvent`.

**Rationale:** AX is the most behaviorally correct path — it's the same code path the user would invoke manually. Cmd+W is the universal keyboard fallback for the small set of windows that don't expose AX close buttons cleanly.

**Alternatives considered:**
- `Cmd+W` only. Rejected: in apps where Cmd+W closes a tab rather than the window (Chrome, VS Code), this would close one tab per window iteration and never satisfy the "window is gone" condition.
- AppleScript `tell application X to close window N`. Rejected: per-app brittleness; every app gets its own scripting dialect.
- Posting `Cmd+Q` to quit apps wholesale. Rejected: would close windows on other Spaces too.

### Decision: Window enumeration uses `CGSCopySpacesForWindows`, filtered by id64

Use the CGS function to get the list of Space id64s each window appears in, filtered to those that contain the target Space's id64. Drop windows that appear in more than one Space (sticky / all-desktops) or whose Space list contains the special "all" sentinel.

**Rationale:** `CGSCopySpacesForWindows` is the same API class that `SpaceDetector` already uses; it gives us the exact filter we need without touching the AX tree.

**Alternatives considered:**
- `CGWindowListCopyWindowInfo` + per-window Space inspection. Rejected: doesn't expose Space membership; we'd still end up calling the CGS function for each window.
- Walking AX trees to find windows. Rejected: AX has no Space concept; we'd have to correlate via window IDs anyway.

### Decision: Shutdown-style sheet with no-progress timer, not a fixed deadline

The progress sheet shows one row per target window (`⋯` pending, `⏳` close-in-flight, `✓` confirmed gone). A 30-second "no progress" timer counts down only while no window has closed; any successful close resets it. If the timer reaches zero, the operation auto-cancels — already-closed windows stay closed, the project record is untouched, and the user is shown which windows remained.

**Rationale:** A fixed deadline punishes users who legitimately need to interact with multiple save dialogs. A no-progress timer punishes only the "something is genuinely stuck" case.

**Alternatives considered:**
- Per-window timeout. Rejected: too granular; surfaces confusing partial states.
- No timeout at all. Rejected: a misbehaving app would leave the sheet stuck forever.
- macOS-style "These apps prevent restart" final list. We borrow the visual idiom but don't hard-block — we let the user cancel any time.

### Decision: Archive is metadata-only; rehydration happens via reassignment

`archived: true` strips `space`, `space_id64`, `path`, `claude_enabled` and hides the project from the menu bar. It preserves `id`, `name`, `github_issues`, `github_prs`, `links`, `openspec_change`, `summary`. Restore = set `archived: false`; the project becomes unassigned (per stable-space-tracking) until the user picks a Space.

**Rationale:** "Re-open the windows / re-launch the apps" is a much bigger feature and not what the user asked for. The metadata-preservation use case is "remember what this project was about so I can find it later" — that's a small, easy-to-deliver win.

**Alternatives considered:**
- Preserving `path` on archive. Considered, deferred: the user said "just the metadata," and `path` plus `claude_enabled` are tied to active monitoring. They re-acquire on restore.
- A separate archived-projects file. Rejected: more storage complexity for no benefit; same JSON, one new field.

### Decision: Fullscreen-Space detection via the CGS Space type, refused at confirm time

Each Space dictionary returned by `CGSCopyManagedDisplaySpaces` includes a `type` field (0 = user, 4 = fullscreen-app, others). When the target project's Space has `type != 0`, the confirm dialog refuses with copy directing the user to exit fullscreen first.

**Rationale:** Fullscreen Spaces are owned by an app. Closing the app's window collapses the Space, which provokes a renumber while the user is mid-flow. Avoiding the path entirely is simpler than handling the special case.

### Decision: Close action lives in Edit Projects only, not the menu bar dropdown

The menu bar dropdown is for fast actions (switch / dismiss / open in terminal). Close-project is heavyweight and deliberate; putting it in the editor (where Delete and other persistent edits also live) matches its weight class.

**Rationale:** Friction is the feature. The user shouldn't be one stray click in the menu bar from closing 7 windows.

## Risks / Trade-offs

- **[Risk] AX-driven close on a window with an unresponsive app stalls the close call.** → Mitigation: dispatch each close on a background queue with a per-call timeout (e.g. 2s), then move to the next window. The sheet's no-progress timer covers the macro case.
- **[Risk] User has Accessibility revoked.** Same gating as Space switch: pre-check, surface the existing remediation dialog, do not start the flow.
- **[Risk] User cancels mid-flow after some windows have closed.** Acceptable: the project record is untouched and the user can retry. The sheet's final state shows what closed and what didn't.
- **[Risk] A sticky/all-desktops window we skip turns out to belong only to this project.** Acceptable per the user's stated preference. Such a window is by definition shared across desktops; closing it is the user's call.
- **[Risk] The CGS private functions return unexpected shapes on a future macOS version.** → Mitigation: graceful degradation. If enumeration returns nothing, the confirm dialog says "no windows found on this Space — close anyway?" and the operation skips straight to the project-record step.
- **[Risk] After all targeted windows close, the Space is still empty but the app whose last window we closed may quit (or sit in the dock with no windows).** This matches the user's mental model of "polite close" — same outcome as if they'd hit Cmd+W manually on each window. No special handling.
- **[Trade-off] No multi-display addressing.** Same posture as projecthub overall. A project's id64 lives on whichever display it lives on; window enumeration walks all displays' Space lists, same as `SpaceDetector`.

## Migration Plan

No file-format migration. `archived` is additive and defaults to false; older binaries round-trip it through the extras bucket. Existing projects start unarchived and are unaffected.

## Open Questions

- **Sheet visual presentation.** Modal to Edit Projects, or modal to the app? Probably modal-to-Edit-Projects so the user can still see the rest of their project list. Defer to implementation.
- **What does "Restore" do beyond clearing `archived`?** Probably opens Edit Projects and scrolls to the restored row so the user can immediately pick a Space. Defer to implementation taste.
- **Archived-section ordering.** Alphabetical, or last-archived-first? Defer.
- **Per-window AX timeout value.** 2s is a guess; tune empirically.
