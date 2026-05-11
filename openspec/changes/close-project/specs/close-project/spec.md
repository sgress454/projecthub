## ADDED Requirements

### Requirement: Close-project entry point and confirmation

The app SHALL expose a "Close…" action on each active project's row in the Edit Projects window. Clicking the action SHALL present a modal confirmation showing the count of windows currently on the project's Space, the count of windows skipped because they are pinned to multiple/all desktops, and three options: Cancel, Archive, and Delete & Close Windows. The confirmation SHALL NOT be present in the menu bar dropdown.

#### Scenario: Close action available in editor only

- **GIVEN** the user has an active project
- **WHEN** the user opens Edit Projects
- **THEN** a "Close…" control is visible on that project's row
- **AND** no Close control is exposed in the menu bar dropdown

#### Scenario: Confirmation summarizes the operation

- **GIVEN** a project is on a Space with 7 closeable windows and 2 windows pinned to all desktops
- **WHEN** the user clicks "Close…"
- **THEN** the confirmation reports "7 windows will be closed" and "2 windows pinned to all desktops will be skipped"
- **AND** the confirmation offers Cancel, Archive, and Delete & Close Windows

#### Scenario: Cancel closes the dialog without changes

- **WHEN** the user clicks Cancel in the confirmation
- **THEN** no windows are closed, the project record is unchanged, and the dialog dismisses

### Requirement: Refusal on fullscreen-app Spaces

When the project's assigned Space is occupied by a fullscreen application (CGS Space type ≠ user-Space), the app SHALL refuse the close operation. The confirmation SHALL display copy directing the user to exit fullscreen mode for that app, and SHALL NOT offer the Archive or Delete buttons.

#### Scenario: Fullscreen Space is detected

- **GIVEN** a project's assigned Space has a non-user CGS type
- **WHEN** the user clicks "Close…" for that project
- **THEN** the confirmation states that the Space is occupied by a fullscreen app and instructs the user to exit fullscreen first
- **AND** only a Cancel/OK button is offered (no Archive, no Delete)

### Requirement: Window enumeration excludes sticky windows

The app SHALL enumerate the closeable windows on the project's Space using the CoreGraphics Spaces API, identifying each window by its Space membership. Windows that appear in more than one Space, or whose Space membership includes the all-spaces sentinel, SHALL be excluded from the closeable set and reported as "skipped" in the confirmation.

#### Scenario: Sticky window is skipped

- **GIVEN** a Chrome window is pinned to all desktops while the user has a project on Space 4
- **WHEN** the close-project flow enumerates windows on Space 4
- **THEN** the Chrome window is reported as a skipped sticky window and is not included in the close set

#### Scenario: Window appearing in multiple specific Spaces is skipped

- **GIVEN** a window appears on Spaces 2 and 4 (without the all-spaces sentinel)
- **WHEN** the close-project flow enumerates windows on Space 4
- **THEN** the window is treated as sticky and is not included in the close set

### Requirement: Shutdown-style progress sheet with no-progress timeout

After the user confirms, the app SHALL display a progress sheet listing each window in the close set with its app icon, app name, window title, and current state (`pending` / `closing` / `closed` / `failed`). The sheet SHALL also display a no-progress countdown that decrements only while no window has transitioned to `closed`. Each successful close SHALL reset the countdown to its initial value. If the countdown reaches zero, the operation SHALL be cancelled. The sheet SHALL provide a Cancel control that the user MAY invoke at any time.

#### Scenario: Progress advances per window

- **GIVEN** the close set contains 5 windows and the operation is running
- **WHEN** windows close one at a time
- **THEN** each window's row transitions from `pending` → `closing` → `closed` and the countdown resets on each closure

#### Scenario: No-progress timer expiry cancels the operation

- **GIVEN** the close-project flow is running and 30 seconds elapse without any window transitioning to `closed`
- **WHEN** the timer reaches zero
- **THEN** the operation is cancelled, no further close calls are issued, and the sheet displays the final state

#### Scenario: User cancellation halts the flow

- **GIVEN** the close-project flow is running
- **WHEN** the user clicks Cancel
- **THEN** no further close calls are issued, in-flight close calls are allowed to complete, and the sheet finalizes with the current state

#### Scenario: Successful close updates project record

- **GIVEN** every window in the close set has transitioned to `closed`
- **WHEN** the operation completes
- **THEN** the project record is updated according to the user's choice (Archive sets `archived=true` and strips space/path; Delete & Close removes the project entry)

#### Scenario: Cancelled or partial close leaves project record unchanged

- **GIVEN** the operation cancels or times out before every window in the close set is closed
- **WHEN** the sheet finalizes
- **THEN** already-closed windows remain closed AND the project record is NOT modified (project entry preserved, archived flag unchanged)

### Requirement: Window-close path uses AX with Cmd+W fallback

For each window in the close set, the app SHALL first attempt to invoke the window's AX close button via `AXUIElementPerformAction`. If the AX close button is not exposed or the action fails, the app SHALL fall back to focusing the window and posting a `Cmd+W` keystroke via `CGEvent`. The app SHALL NOT post `Cmd+Q` and SHALL NOT use AppleScript or per-app heuristics. The app SHALL apply a per-window timeout (default 2 seconds) so that an unresponsive app does not stall the entire flow.

#### Scenario: AX close path used by default

- **GIVEN** a target window exposes a usable AX close button
- **WHEN** the close-project flow processes that window
- **THEN** `AXUIElementPerformAction(closeButton, kAXPressAction)` is invoked

#### Scenario: Cmd+W fallback when AX is unavailable

- **GIVEN** a target window has no usable AX close button
- **WHEN** the close-project flow processes that window
- **THEN** the window is focused and `Cmd+W` is posted via `CGEvent`

#### Scenario: Per-window timeout protects the flow

- **GIVEN** a target window's app stops responding to its close call
- **WHEN** 2 seconds elapse without the window disappearing
- **THEN** the flow records the window as `failed` and continues with the next window

### Requirement: Save-prompt handling delegated to the OS

The app SHALL NOT attempt to dismiss, suppress, or auto-respond to any unsaved-work or save-confirmation dialogs presented by other apps during the close flow. The user SHALL be solely responsible for resolving such dialogs. While such a dialog is unresolved, the corresponding window SHALL remain in the `closing` state and SHALL NOT contribute to the no-progress countdown's reset.

#### Scenario: Save dialog blocks a window's closure

- **GIVEN** a target window has unsaved changes
- **WHEN** the close call is made and the app's save dialog appears
- **THEN** the corresponding sheet row remains in `closing` state until the user resolves the save dialog
- **AND** the no-progress timer continues to count down (as no closure has occurred)

#### Scenario: User saves and the window closes

- **GIVEN** an app's save dialog is up because of the close-project flow
- **WHEN** the user accepts the save
- **THEN** the window closes, the sheet row transitions to `closed`, and the no-progress timer resets

#### Scenario: User cancels the save dialog

- **GIVEN** an app's save dialog is up
- **WHEN** the user cancels the save (which generally cancels the close)
- **THEN** the window remains open, the sheet row stays in `closing` until the per-window timeout, and is then marked `failed`

### Requirement: Archive disposition preserves metadata

When the user chooses Archive at the confirmation, and the close flow completes successfully, the app SHALL set `archived = true` on the project and clear `space`, `space_id64`, `path`, and `claude_enabled`. The project SHALL retain its `id`, `name`, `github_issues`, `github_prs`, `links`, `openspec_change`, and `summary`.

#### Scenario: Archive strips Space and monitoring fields

- **GIVEN** a project with name, Space 4, path, claude_enabled true, links, GitHub PRs
- **WHEN** the user successfully closes it via Archive
- **THEN** the persisted project has `archived = true`, no `space`, no `space_id64`, no `path`, `claude_enabled = false`, AND its name, links, and GitHub PRs are intact

#### Scenario: Restore returns project to unassigned active state

- **GIVEN** an archived project with metadata preserved
- **WHEN** the user clicks Restore in the Edit Projects Archived section
- **THEN** `archived` becomes false, the project enters the unassigned state (per stable-space-tracking), and is hidden from the menu bar until the user picks a Space

### Requirement: Delete disposition removes the project entirely

When the user chooses Delete & Close Windows at the confirmation, and the close flow completes successfully, the app SHALL remove the project from `projects.json` entirely.

#### Scenario: Delete removes the entry

- **GIVEN** a project with metadata
- **WHEN** the user successfully closes it via Delete & Close Windows
- **THEN** the project is removed from `projects.json` and is not visible in the menu bar or Edit Projects (active or archived sections)

### Requirement: Empty Space is left for the user to close

After the close flow completes (Archive or Delete), the app SHALL NOT attempt to remove the now-empty Space from macOS. The user is expected to close the empty Space manually via Mission Control. The `stable-space-tracking` capability SHALL detect the resulting Space-shape change and renumber other projects' positional Space values automatically.

#### Scenario: Empty Space remains until manual closure

- **GIVEN** the close-project flow has just completed for a project on Space 4
- **WHEN** the operation finalizes
- **THEN** Space 4 still exists in macOS Mission Control (now empty) and the app does not attempt to remove it

#### Scenario: Manual Space closure triggers renumber

- **GIVEN** the user closes the empty Space 4 in Mission Control
- **WHEN** the resulting Space-shape change fires
- **THEN** other projects whose `space_id64` corresponds to positions above 4 have their `space` decremented by one, per the stable-space-tracking capability
