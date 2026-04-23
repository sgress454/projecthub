## MODIFIED Requirements

### Requirement: Project list persistence

The app SHALL persist a user-editable list of projects across launches. Each project has at minimum a human-readable name and an assigned Space number in the range 1-9. Each project MAY additionally have: a list of GitHub issue URLs, a list of GitHub PR URLs (with a flag distinguishing manually-added from auto-discovered), a list of labeled links (URL + label), an OpenSpec change name, and a cached AI summary string.

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

### Requirement: Storage schema version 3

The app SHALL write `projects.json` with `version` set to `3`, SHALL preserve existing v1 and v2 files on read without requiring migration, and SHALL continue to round-trip unknown fields per the forward-compatibility guarantee.

#### Scenario: New files are written with version 3

- **WHEN** the app saves the store after any edit
- **THEN** the written file has `"version": 3` at the top level

#### Scenario: Version 2 files load without error

- **GIVEN** a `projects.json` file with `"version": 2`
- **WHEN** the app starts
- **THEN** the file loads successfully, all projects are available, and metadata fields default to empty/nil

#### Scenario: Version 1 files load without error

- **GIVEN** a `projects.json` file with `"version": 1`
- **WHEN** the app starts
- **THEN** the file loads successfully, all projects are available, `claude_enabled` is false, and metadata fields default to empty/nil

#### Scenario: Unknown fields are preserved

- **GIVEN** a `projects.json` file contains fields not defined by the current schema
- **WHEN** the app saves the file after an edit
- **THEN** those unknown fields are preserved on disk

### Requirement: Per-row dismiss control

Each project row SHALL display a dismiss control (a small "x" button or equivalent affordance) when its color state is `red` or `yellow`. Clicking the control SHALL invoke the dismiss action for that project and close the menu, without switching Spaces. The control SHALL be hidden when the color state is `green`.

#### Scenario: Dismiss control visible on yellow

- **GIVEN** a project's state is `yellow`
- **WHEN** the user opens the menu bar dropdown
- **THEN** the row shows a trailing dismiss control

#### Scenario: Dismiss control visible on red

- **GIVEN** a project's state is `red`
- **WHEN** the user opens the menu bar dropdown
- **THEN** the row shows a trailing dismiss control

#### Scenario: Dismiss control hidden on green

- **GIVEN** a project's state is `green`
- **WHEN** the user opens the menu bar dropdown
- **THEN** the row does NOT show a dismiss control

#### Scenario: Clicking dismiss does not switch Spaces

- **GIVEN** a red or yellow project is visible in the menu
- **WHEN** the user clicks the dismiss control
- **THEN** the project's state clears to green AND macOS does NOT switch to that project's Space AND the menu closes
