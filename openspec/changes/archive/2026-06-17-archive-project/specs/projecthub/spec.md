## MODIFIED Requirements

### Requirement: Project list persistence

The app SHALL persist a user-editable list of projects across launches. Each project has at minimum a human-readable name and a Space number (in the range 0-16; the value 0 is reserved as the "no positional assignment" sentinel for unassigned-active and archived projects, while 1-16 are real macOS Space positions). Each project MAY additionally have: a list of GitHub issue URLs, a list of GitHub PR URLs (with a flag distinguishing manually-added from auto-discovered), a list of labeled links (URL + label), an OpenSpec change name, a cached AI summary string, a cached stable Space identifier (`space_id64`), an `archived` boolean (default false), and an `archived_at` ISO8601 timestamp (set when the project is archived, nil otherwise). Archived projects retain their identity and metadata but SHALL have `space = 0`, no `space_id64`, no `path`, and `claude_enabled = false`, so they are excluded from all Space-related code paths (switch, active-highlight, lazy-capture, hook routing).

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

#### Scenario: Archived projects round-trip metadata

- **GIVEN** a project archived with name, links, GitHub issues, GitHub PRs, OpenSpec change, and summary
- **WHEN** the app saves and reloads `projects.json`
- **THEN** the project loads with `archived = true`, `archived_at` set to the original archive moment, all metadata intact, `space = 0`, `space_id64` absent, `path` absent, and `claude_enabled = false`

#### Scenario: archived_at preserves ordering across launches

- **GIVEN** two projects archived at different times (project A at T, project B at T+1)
- **WHEN** the app saves and reloads `projects.json`
- **THEN** both projects load with their original `archived_at` values intact, and the archived list orders B before A (last-archived-first)

#### Scenario: Pre-archive files load without archived

- **GIVEN** a `projects.json` file written before archive-project
- **WHEN** the app reads the file
- **THEN** each project loads with `archived = false` and `archived_at = nil`, and no error is raised

### Requirement: Menu bar project list

The app SHALL show the project list in a macOS menu bar dropdown with each project's name visible at a glance. The assigned Space number SHALL NOT be displayed in the menu bar row; it remains visible and editable in the Edit Projects window. Archived projects SHALL NOT appear in the menu bar list.

#### Scenario: Listing projects

- **WHEN** the user has configured three projects A/1, B/2, C/3 and clicks the menu bar icon
- **THEN** the dropdown shows three rows, each with the project name
- **AND** no row displays the text "Space 1", "Space 2", or "Space 3"

#### Scenario: Empty-state

- **WHEN** no projects are configured and the user clicks the menu bar icon
- **THEN** the dropdown shows a single row inviting the user to add their first project, which opens the Edit Projects window when clicked

#### Scenario: Space number remains in Edit Projects window

- **GIVEN** project "api" is mapped to Space 3
- **WHEN** the user opens the Edit Projects window
- **THEN** the Space number "3" is displayed alongside the project's name

#### Scenario: Archived projects are excluded from the menu

- **GIVEN** the user has two active projects and one archived project
- **WHEN** the user clicks the menu bar icon
- **THEN** the dropdown shows only the two active projects and no row for the archived one

### Requirement: Editing the project list

The app SHALL provide a dedicated editor window for adding, renaming, removing, reassigning, archiving, and restoring projects. Archived projects SHALL be presented in a dedicated section, separate from active projects.

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

#### Scenario: Archiving a project from the editor

- **GIVEN** an active project is visible in Edit Projects
- **WHEN** the user clicks "Archive" on that project's row
- **THEN** the project is immediately archived (no confirmation dialog), its row disappears from the active list, and it appears at the top of the Archived section

#### Scenario: Archived section lists archived projects

- **GIVEN** the user has archived one or more projects
- **WHEN** the user opens Edit Projects
- **THEN** an "Archived" section is visible (collapsed by default) listing each archived project with name and a Restore action, ordered by `archived_at` descending (last-archived-first)

#### Scenario: Restoring an archived project

- **GIVEN** an archived project is visible in the Archived section
- **WHEN** the user clicks Restore
- **THEN** the project's `archived` flag clears, `archived_at` clears, the project returns to the active list in the unassigned-active state (`space = 0`, `spaceID64 = nil`, no path), is rendered in the menu bar as a disabled row consistent with the existing unassigned treatment, and the user assigns a Space via the row's Space picker to make it usable
