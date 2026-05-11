## 1. Storage and model

- [ ] 1.1 Add an `archived: Bool` field to `Project` (default false), with `archived` JSON key, encoded only when true (omit-when-default mirrors the existing metadata-field pattern).
- [ ] 1.2 Add an `archive()` helper on `Project` that returns a copy with `archived = true`, `space = nil`, `spaceID64 = nil`, `path = nil`, `claudeEnabled = false`, all other metadata intact.
- [ ] 1.3 Update `ProjectStore` so menu-bar reads filter out archived projects but Edit Projects sees the full list.
- [ ] 1.4 Unit-test archive round-trip: archive → save → load → restore (clear archived) → re-edit, with all preserved fields intact.

## 2. Window enumeration

- [ ] 2.1 Add `WindowEnumerator` (Sources/ProjectHubKit) with a function `windowsOn(spaceID64:) -> [WindowRef]`. Use `CGSCopyWindowsWithOptionsAndTags` to list all windows, then `CGSCopySpacesForWindows` to filter by id64.
- [ ] 2.2 Tag each result with whether it's sticky / all-desktops (appears in >1 Space or contains the all-spaces sentinel) so the enumerator can return only the closeable subset by default and the sticky-skip count for the confirm dialog.
- [ ] 2.3 Resolve each `WindowRef` to a human-readable title (owning app name + window title) for display in the progress sheet — read via `CGWindowListCopyWindowInfo` filtered by window ID.
- [ ] 2.4 Unit-test the enumerator against synthetic CGS responses (single Space, multiple Spaces, sticky window, all-spaces sentinel).

## 3. Window closing

- [ ] 3.1 Add `WindowCloser` with `close(window:) async -> CloseResult` (success / failed / timed-out). Implementation order: AX `AXCloseButton.performAction` first (resolved via window owner PID + window ID matching against `AXUIElementCreateApplication` children), Cmd+W keystroke fallback after focusing the window.
- [ ] 3.2 Per-window timeout (start with 2s) so an unresponsive app doesn't stall the entire flow.
- [ ] 3.3 Polling/observation to confirm window has actually disappeared from the target Space (re-enumerate after close attempt).
- [ ] 3.4 Unit-test the dispatch logic with a stub `WindowCloser` (the AX/CGS calls themselves require a UI test or manual verification).

## 4. Coordinator and progress sheet

- [ ] 4.1 Add `CloseProjectCoordinator` that takes a `Project`, runs enumeration, presents the confirm dialog, presents the progress sheet, drives `WindowCloser` over the closeable set, and returns a final result (cancelled, completed, partial).
- [ ] 4.2 Implement the progress sheet as a SwiftUI view hosted via `NSHostingController`, mirroring the Edit Projects window's tech stack. Each row displays app icon + title + state (`⋯`/`⏳`/`✓`/`✗`).
- [ ] 4.3 Implement the no-progress timer: 30s countdown, reset on every successful close, expiry triggers cancel.
- [ ] 4.4 Implement the cancel button: stops issuing new close calls; lets in-flight ones finish; finalizes the sheet state.
- [ ] 4.5 On final completion (or cancel-with-some-closed), apply the user's chosen project disposition (delete or archive) to `ProjectStore`.

## 5. Confirm dialog and refusal paths

- [ ] 5.1 Build the confirm dialog (NSAlert or hosted SwiftUI) showing window count, sticky-skip count, fullscreen-detection result, and three buttons: Cancel / Archive / Delete & Close Windows.
- [ ] 5.2 Detect fullscreen Space via `CGSCopyManagedDisplaySpaces` Space `type` field (≠ 0); show "exit fullscreen first" copy and remove the Archive/Delete buttons.
- [ ] 5.3 Detect missing Accessibility permission and short-circuit to the existing remediation dialog before window enumeration.
- [ ] 5.4 Detect "no windows found on this Space" (likely a CGS-shape change) and offer "Archive without closing" / "Delete without closing" / "Cancel".

## 6. Edit Projects window integration

- [ ] 6.1 Add a "Close…" button to each project row in Edit Projects (next to Delete or replacing it).
- [ ] 6.2 Add an "Archived" disclosure section below the active list, populated from `ProjectStore`'s archived rows.
- [ ] 6.3 Add a "Restore" button on archived rows that clears `archived` and (optionally) opens the Space picker for that project.
- [ ] 6.4 Confirm the menu bar list excludes archived projects (no row, no badge contribution, no path matching).

## 7. Spec updates

- [ ] 7.1 New `close-project` spec authored in change folder.
- [ ] 7.2 `MODIFIED` requirement: project list persistence (adds `archived`).
- [ ] 7.3 `MODIFIED` requirement: menu bar project list (excludes archived).
- [ ] 7.4 `MODIFIED` requirement: editing the project list (Close button, Archived section, Restore).

## 8. Manual verification

- [ ] 8.1 Set up a project on its own Space with 5+ windows from different apps (browser, terminal, editor, Slack). Click Close → Delete & Close Windows. Confirm windows close one by one, project is removed, no error.
- [ ] 8.2 Pin a Chrome window to all desktops; confirm the confirm dialog reports it as a skipped sticky window and the close flow leaves it alone.
- [ ] 8.3 Open an editor with unsaved changes; Click Close → Delete & Close Windows. Confirm the editor's save dialog appears and that ProjectHub's progress row stays in `⏳` state until the user resolves it.
- [ ] 8.4 Trigger no-progress timeout: open a save dialog and ignore it for 30s. Confirm the operation auto-cancels and the project record is untouched.
- [ ] 8.5 Switch a project's Space to be fullscreen-occupied (drag a fullscreen app's Space into position). Click Close. Confirm refusal copy and no enumeration occurs.
- [ ] 8.6 After successful close, manually close the now-empty Space in Mission Control. Confirm `stable-space-tracking` renumbers other projects.
- [ ] 8.7 Click Close → Archive on a project. Confirm windows close, the project moves to the Archived section in Edit Projects, and the menu bar no longer shows it. Restore the project; confirm metadata round-trips and the project becomes unassigned.
- [ ] 8.8 Quit and relaunch with archived projects in the store; confirm they reload as archived.
