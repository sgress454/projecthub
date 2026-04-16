## ADDED Requirements

### Requirement: Per-project GitHub issue links

Each project SHALL support a list of zero or more GitHub issue URLs. Issues are manually added and removed by the user via the metadata editing modal.

#### Scenario: Adding a GitHub issue URL

- **WHEN** the user opens the metadata modal for a project and adds a valid GitHub issue URL
- **THEN** the URL is stored on the project and persisted to disk

#### Scenario: Removing a GitHub issue URL

- **WHEN** the user removes a GitHub issue URL from the metadata modal
- **THEN** the URL is removed from the project and the change is persisted

#### Scenario: Issue title is fetched on add

- **WHEN** the user adds a GitHub issue URL and `gh` is available and authenticated
- **THEN** the app fetches the issue title via `gh issue view` for display in the submenu

#### Scenario: Issue title fetch fails gracefully

- **WHEN** the user adds a GitHub issue URL and `gh` is unavailable or the fetch fails
- **THEN** the URL is still stored and displayed using the issue number extracted from the URL (e.g., "#42")

### Requirement: Per-project GitHub PR links

Each project SHALL support a list of zero or more GitHub PR URLs. PRs may be added manually or discovered automatically. Manually added PRs SHALL be distinguishable from auto-discovered PRs so that auto-discovery does not remove them.

#### Scenario: Adding a PR URL manually

- **WHEN** the user adds a GitHub PR URL via the metadata modal
- **THEN** the URL is stored as a manually-added PR and persisted

#### Scenario: Auto-discovered PRs are merged with manual PRs

- **WHEN** GitHub sync discovers PRs for a project's branch
- **THEN** the discovered PRs are added alongside any manually-added PRs, without duplicates

#### Scenario: Auto-discovered PRs can be removed by sync

- **WHEN** a previously auto-discovered PR is no longer returned by `gh pr list` (e.g., branch changed)
- **THEN** the auto-discovered entry is removed, but manually-added PRs are unaffected

### Requirement: Per-project arbitrary links

Each project SHALL support a list of zero or more labeled links (a URL and a human-readable label). These are manually managed by the user.

#### Scenario: Adding a labeled link

- **WHEN** the user adds a link with URL "https://figma.com/..." and label "Design mockups" in the metadata modal
- **THEN** the link is stored and persisted on the project

#### Scenario: Removing a labeled link

- **WHEN** the user removes a labeled link from the metadata modal
- **THEN** the link is removed from the project and the change is persisted

### Requirement: Per-project OpenSpec change association

Each project SHALL support an optional association with a single OpenSpec change by name. The association MAY be auto-detected or manually set.

#### Scenario: Auto-detection with exactly one active change

- **GIVEN** a project has a `path` set and `<path>/openspec/changes/` contains exactly one non-archive subdirectory
- **WHEN** the project is loaded or its path changes
- **THEN** the `openspecChange` field is auto-populated with that change's name

#### Scenario: Auto-detection with zero or multiple changes

- **GIVEN** a project has a `path` set and `<path>/openspec/changes/` contains zero or more than one non-archive subdirectory
- **WHEN** the project is loaded or its path changes
- **THEN** the `openspecChange` field is left nil (no auto-detection)

#### Scenario: Manual override

- **WHEN** the user selects a change name from the dropdown in the metadata modal
- **THEN** the `openspecChange` field is set to that value, overriding any auto-detection

#### Scenario: OpenSpec directory not present

- **GIVEN** a project's path does not contain an `openspec/changes/` directory
- **WHEN** auto-detection runs
- **THEN** the `openspecChange` field is left nil and no error is raised

### Requirement: Metadata editing modal

The Edit Projects window SHALL provide a per-project button that opens a metadata editing modal. The modal SHALL allow the user to add and remove GitHub issues, PRs, arbitrary links, and select an OpenSpec change.

#### Scenario: Opening the metadata modal

- **WHEN** the user clicks the metadata button on a project row in the Edit Projects window
- **THEN** a modal sheet appears with sections for GitHub Issues, Pull Requests, Links, and OpenSpec Change

#### Scenario: Changes are saved on close

- **WHEN** the user closes the metadata modal
- **THEN** all changes made in the modal are persisted to the project store

#### Scenario: gh CLI not available hint

- **GIVEN** the `gh` CLI is not installed or not authenticated
- **WHEN** the user opens the metadata modal
- **THEN** an inline hint explains that installing and authenticating `gh` enables PR auto-discovery and issue title fetching
