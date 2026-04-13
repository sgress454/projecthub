## ADDED Requirements

### Requirement: Project list persistence

The app SHALL persist a user-editable list of projects across launches. Each project has at minimum a human-readable name and an assigned Space number in the range 1–9.

#### Scenario: Saving a project survives app restart

- **WHEN** the user adds a project with name "claude-usage-bar" and Space 1, then quits and relaunches the app
- **THEN** the menu bar list still shows "claude-usage-bar" mapped to Space 1

#### Scenario: First launch with no saved list

- **WHEN** the app launches for the first time with no existing storage file
- **THEN** the menu bar shows an empty-state prompt to add the first project, and no error is raised

#### Scenario: Storage preserves unknown fields

- **WHEN** the storage file on disk contains per-project fields not recognized by v0.1 (e.g. a `path` field added by a future version)
- **THEN** the app loads and saves without discarding those fields

### Requirement: Menu bar project list

The app SHALL show the project list in a macOS menu bar dropdown with each project's name and Space number visible at a glance.

#### Scenario: Listing projects

- **WHEN** the user has configured three projects A/1, B/2, C/3 and clicks the menu bar icon
- **THEN** the dropdown shows three rows, each with the project name and Space number

#### Scenario: Empty-state

- **WHEN** no projects are configured and the user clicks the menu bar icon
- **THEN** the dropdown shows a single row inviting the user to add their first project, which opens the Edit Projects window when clicked

### Requirement: Switch to project's Space on click

The app SHALL switch macOS to the assigned Space when a project row is clicked in the menu bar dropdown.

#### Scenario: Clicking a project switches Space

- **GIVEN** the user is currently on Space 1 and has a project "api-refactor" mapped to Space 3
- **WHEN** the user clicks the "api-refactor" row in the menu bar
- **THEN** macOS switches to Space 3

#### Scenario: Accessibility permission missing

- **GIVEN** the app does not yet have Accessibility permission
- **WHEN** the user clicks a project row
- **THEN** the app shows a dialog explaining the permission requirement and offering a button that deep-links to System Settings → Privacy & Security → Accessibility

### Requirement: Editing the project list

The app SHALL provide a dedicated editor window for adding, renaming, removing, and reassigning projects.

#### Scenario: Adding a project

- **WHEN** the user opens the editor and clicks the add button
- **THEN** a new project row appears with an editable name and a Space picker for values 1–9, and the addition is persisted on edit

#### Scenario: Removing a project

- **WHEN** the user deletes a project row in the editor
- **THEN** the project is removed from storage and no longer appears in the menu bar list

#### Scenario: Changing the Space assignment

- **WHEN** the user changes a project's Space from 2 to 5 in the editor
- **THEN** the menu bar list reflects the new assignment and clicking the row now switches to Space 5

#### Scenario: Space number out of range

- **WHEN** the user attempts to assign a project to a Space outside 1–9
- **THEN** the editor prevents the assignment (the picker only offers valid values)

### Requirement: Active-Space highlighting (best-effort)

The app SHOULD highlight the row whose Space is currently active, and SHALL degrade gracefully if the underlying macOS APIs are unavailable or fail.

#### Scenario: Highlight reflects active Space

- **GIVEN** the user has projects mapped to Spaces 1, 2, and 3, and is currently on Space 2
- **WHEN** the user opens the menu bar dropdown
- **THEN** the project row mapped to Space 2 is visually distinguished from the others

#### Scenario: Active-Space detection unavailable

- **WHEN** the underlying active-Space API call fails or returns no value
- **THEN** no row is highlighted, the menu bar list still renders correctly, and clicking a row still switches Spaces

### Requirement: First-run guidance

On first launch, the app SHALL guide the user through the one-time setup required for Space switching to work: granting Accessibility permission and confirming the two required macOS Mission Control settings.

#### Scenario: First-launch onboarding

- **WHEN** the app launches for the first time
- **THEN** an onboarding window appears describing: (a) the Accessibility permission requirement, (b) that "Switch to Desktop N" shortcuts must be enabled, and (c) that "Automatically rearrange Spaces based on most recent use" must be disabled, with deep links to each settings pane

#### Scenario: Permission revoked after first run

- **WHEN** the user revokes Accessibility permission after first run and then clicks a project row
- **THEN** the app detects the missing permission and presents the same remediation dialog as the initial prompt
