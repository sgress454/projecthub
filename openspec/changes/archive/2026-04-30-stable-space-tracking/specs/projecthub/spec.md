## MODIFIED Requirements

### Requirement: Project list persistence

The app SHALL persist a user-editable list of projects across launches. Each project has at minimum a human-readable name and an assigned Space number in the range 1-16. Each project MAY additionally have: a list of GitHub issue URLs, a list of GitHub PR URLs (with a flag distinguishing manually-added from auto-discovered), a list of labeled links (URL + label), an OpenSpec change name, a cached AI summary string, and a cached stable Space identifier (`space_id64`) used to track the project's Space across reorderings or removals.

#### Scenario: Saving a project survives app restart

- **WHEN** the user adds a project with name "claude-usage-bar" and Space 1, then quits and relaunches the app
- **THEN** the menu bar list still shows "claude-usage-bar" mapped to Space 1

#### Scenario: First launch with no saved list

- **WHEN** the app launches for the first time with no existing storage file
- **THEN** the menu bar shows an empty-state prompt to add the first project, and no error is raised

#### Scenario: Storage preserves unknown fields

- **WHEN** the storage file on disk contains per-project fields not recognized by the current version
- **THEN** the app loads and saves without discarding those fields

#### Scenario: Metadata fields persist across launches

- **GIVEN** a project has GitHub issues, PRs, links, an OpenSpec change, and a cached summary
- **WHEN** the app quits and relaunches
- **THEN** all metadata fields are restored to their saved values

#### Scenario: Metadata fields default to empty on upgrade

- **GIVEN** a `projects.json` file written by v2 (no metadata fields)
- **WHEN** the app reads the file
- **THEN** each project loads with empty issue/PR/link lists, nil OpenSpec change, and nil summary

#### Scenario: Cached Space identifier round-trips

- **GIVEN** a project with `space_id64` set
- **WHEN** the app saves and reloads `projects.json`
- **THEN** the same `space_id64` value is restored on that project

#### Scenario: Pre-upgrade files load without space_id64

- **GIVEN** a `projects.json` file written before stable-space-tracking
- **WHEN** the app reads the file
- **THEN** each project loads with `space_id64` absent, and no error is raised

### Requirement: Switch to project's Space on click

The app SHALL switch macOS to the assigned Space when a project row is clicked in the menu bar dropdown. If the project's cached `space_id64` no longer corresponds to a live Space (the Space was removed), the click SHALL NOT post a keystroke and SHALL surface the reassignment affordance instead. If the "Switch to Desktop N" keyboard shortcut required for the target Space is not enabled in macOS Keyboard Shortcuts, the app SHALL surface an actionable dialog identifying the missing shortcut and offering a deep-link to the Keyboard Shortcuts pane, rather than silently posting a keypress that macOS rejects.

#### Scenario: Clicking a project switches Space

- **GIVEN** the user is currently on Space 1 and has a project "api-refactor" mapped to Space 3
- **WHEN** the user clicks the "api-refactor" row in the menu bar
- **THEN** macOS switches to Space 3

#### Scenario: Accessibility permission missing

- **GIVEN** the app does not yet have Accessibility permission
- **WHEN** the user clicks a project row
- **THEN** the app shows a dialog explaining the permission requirement and offering a button that deep-links to System Settings → Privacy & Security → Accessibility

#### Scenario: Target Space shortcut is not bound

- **GIVEN** the user has a project mapped to Space 9 and "Switch to Desktop 9" is disabled in System Settings → Keyboard → Keyboard Shortcuts → Mission Control
- **WHEN** the user clicks that project's row
- **THEN** the app displays a dialog stating that "Switch to Desktop 9" is not enabled, offers a button that deep-links to the Mission Control Keyboard Shortcuts pane, and does NOT post the `Control+9` keypress

#### Scenario: Shortcut-binding check unavailable

- **WHEN** the app cannot read the symbolic-hotkey preferences (e.g., defaults domain unavailable)
- **THEN** the app posts the keypress as a best-effort fallback rather than blocking the click

#### Scenario: Click on unassigned project opens the editor

- **GIVEN** a project's cached `space_id64` is no longer present in the current Spaces shape
- **WHEN** the user clicks that project's row
- **THEN** the app opens the Edit Projects window focused on that project and does NOT post a keystroke

## ADDED Requirements

### Requirement: Stable Space identity tracking

The app SHALL cache a stable Space identifier (`space_id64`) per project, derived from CoreGraphics' Spaces metadata at the time the project's Space is assigned or first reconciled. The app SHALL re-derive each project's positional `space` value from its cached `space_id64` whenever the macOS Spaces arrangement changes (Spaces added, removed, or reordered). The app SHALL detect arrangement changes via `NSWorkspace.activeSpaceDidChangeNotification`. The user-facing "Space N" model (1–16) is unchanged; `space_id64` is an internal shadow field not surfaced in the editor.

#### Scenario: Reordering Spaces preserves project assignments

- **GIVEN** projects A, B, C are assigned to Spaces 1, 2, 3 with their `space_id64` values cached
- **WHEN** the user reorders the Spaces in Mission Control such that the Space previously at position 3 is now at position 1
- **THEN** project C's `space` updates to 1 and projects A and B shift accordingly, all without user action

#### Scenario: Inserting a new Space shifts higher-positioned projects

- **GIVEN** projects A, B, C are on Spaces 1, 2, 3
- **WHEN** the user adds a new Space between positions 2 and 3 in Mission Control
- **THEN** project C's `space` updates from 3 to 4 and projects A and B remain on 1 and 2

#### Scenario: Removing an unrelated Space shifts higher-positioned projects down

- **GIVEN** projects A, B, C are on Spaces 1, 3, 4 and Space 2 is empty
- **WHEN** the user removes Space 2 in Mission Control
- **THEN** projects B and C update to Spaces 2 and 3, project A remains on Space 1

#### Scenario: Lazy capture populates space_id64 for upgraded projects

- **GIVEN** a project loaded from a pre-upgrade `projects.json` with `space_id64` absent and `space` 2
- **WHEN** the app runs reconciliation against the current Spaces shape and position 2 exists
- **THEN** the project's `space_id64` is populated with that position's identifier and persisted on the next save

#### Scenario: Editor assignment captures space_id64 immediately

- **WHEN** the user changes a project's Space picker to position 5 and that position currently exists
- **THEN** the project's `space_id64` is updated to position 5's current identifier alongside `space`

### Requirement: Unassigned-project rendering when cached Space is missing

When a project's cached `space_id64` is not present in the current Spaces shape (the assigned Space has been removed), the app SHALL render the project in an "unassigned" state: visible in the menu bar and Edit Projects with its name, but with `space` effectively nil. The menu row SHALL be styled as disabled, SHALL surface a hint that the Space was removed, and SHALL NOT contribute to active-Space highlighting or Space-switching.

#### Scenario: Removed-Space project renders disabled

- **GIVEN** a project's cached `space_id64` is no longer present in the current Spaces shape
- **WHEN** the user opens the menu bar dropdown
- **THEN** the project's row appears with disabled styling and a hint indicating the Space was removed

#### Scenario: Reassigning rehydrates the project

- **GIVEN** a project is in the unassigned state
- **WHEN** the user opens Edit Projects and assigns the project to a current Space
- **THEN** both `space` and `space_id64` are updated and the menu bar row returns to normal styling

#### Scenario: Unassigned project does not affect active-Space highlighting

- **GIVEN** a project is in the unassigned state
- **WHEN** the user is on any Space
- **THEN** that project's row is never marked as the active row
