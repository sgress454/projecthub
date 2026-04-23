## MODIFIED Requirements

### Requirement: Project list persistence

The app SHALL persist a user-editable list of projects across launches. Each project has at minimum a human-readable name and an assigned Space number in the range 1-16. Each project MAY additionally have: a list of GitHub issue URLs, a list of GitHub PR URLs (with a flag distinguishing manually-added from auto-discovered), a list of labeled links (URL + label), an OpenSpec change name, and a cached AI summary string.

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

### Requirement: Switch to project's Space on click

The app SHALL switch macOS to the assigned Space when a project row is clicked in the menu bar dropdown. If the "Switch to Desktop N" keyboard shortcut required for the target Space is not enabled in macOS Keyboard Shortcuts, the app SHALL surface an actionable dialog identifying the missing shortcut and offering a deep-link to the Keyboard Shortcuts pane, rather than silently posting a keypress that macOS rejects.

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

### Requirement: Editing the project list

The app SHALL provide a dedicated editor window for adding, renaming, removing, and reassigning projects.

#### Scenario: Adding a project

- **WHEN** the user opens the editor and clicks the add button
- **THEN** a new project row appears with an editable name and a Space picker for values 1–16, and the addition is persisted on edit

#### Scenario: Removing a project

- **WHEN** the user deletes a project row in the editor
- **THEN** the project is removed from storage and no longer appears in the menu bar list

#### Scenario: Changing the Space assignment

- **WHEN** the user changes a project's Space from 2 to 5 in the editor
- **THEN** the menu bar list reflects the new assignment and clicking the row now switches to Space 5

#### Scenario: Space number out of range

- **WHEN** the user attempts to assign a project to a Space outside 1–16
- **THEN** the editor prevents the assignment (the picker only offers valid values)

## ADDED Requirements

### Requirement: Edit Projects window default sort

When the Edit Projects window is opened, the project list SHALL be rendered sorted ascending by Space number, with ties broken by the project's order in the underlying store. The sort order SHALL be applied once per open; edits made while the window is open SHALL NOT cause rows to reshuffle during the session. The underlying stored order of projects SHALL NOT be modified by this sort — the menu bar dropdown and subsequent launches continue to reflect the stored order.

#### Scenario: Opening the editor sorts by Space

- **GIVEN** the store contains projects A/Space 3, B/Space 1, C/Space 2 in that stored order
- **WHEN** the user opens the Edit Projects window
- **THEN** the rows are displayed in the order B (Space 1), C (Space 2), A (Space 3)

#### Scenario: Editing a Space number does not reshuffle the open window

- **GIVEN** the Edit Projects window is open showing rows sorted by Space
- **WHEN** the user changes a project's Space from 2 to 8
- **THEN** the row remains in its current visual position for the remainder of the session

#### Scenario: Stored order is not mutated by the editor's sort

- **GIVEN** the user opens and closes the Edit Projects window without making any edits
- **WHEN** the app subsequently reads `projects.json`
- **THEN** the stored project order is unchanged from before the window was opened
