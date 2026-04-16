## ADDED Requirements

### Requirement: Per-project submenu in menu bar dropdown

Every project row in the menu bar dropdown SHALL have an attached submenu. The submenu SHALL open on hover or arrow interaction per standard NSMenu behavior. Clicking the project row SHALL still switch to that project's Space (existing behavior preserved).

#### Scenario: Hovering a project row opens the submenu

- **WHEN** the user hovers over a project row in the menu bar dropdown
- **THEN** a submenu appears showing the project's linked issues, PRs, other links, and AI summary

#### Scenario: Clicking a project row switches Spaces

- **WHEN** the user clicks a project row in the menu bar dropdown
- **THEN** macOS switches to that project's assigned Space (unchanged from current behavior)

#### Scenario: Submenu present even with no metadata

- **GIVEN** a project has no linked issues, PRs, or other links
- **WHEN** the user hovers to open the submenu
- **THEN** the submenu displays the AI summary (or fallback message) and no link sections

### Requirement: Submenu displays linked GitHub issues

The submenu SHALL display a section for GitHub issues when the project has one or more linked issues.

#### Scenario: Issues shown with title and number

- **GIVEN** a project has linked GitHub issues with fetched titles
- **WHEN** the submenu is open
- **THEN** the issues section shows each issue as "#N — Title"

#### Scenario: Clicking an issue opens it in the browser

- **WHEN** the user clicks a GitHub issue item in the submenu
- **THEN** the issue URL opens in the default browser

### Requirement: Submenu displays linked PRs

The submenu SHALL display a section for GitHub PRs when the project has one or more linked PRs.

#### Scenario: PRs shown with title, state, and comment count

- **GIVEN** a project has linked PRs with cached metadata
- **WHEN** the submenu is open
- **THEN** each PR is shown as "#N — Title" with its state (open/merged/closed) and a count of unresolved reviewer comments if any

#### Scenario: Clicking a PR opens it in the browser

- **WHEN** the user clicks a PR item in the submenu
- **THEN** the PR URL opens in the default browser

### Requirement: Submenu displays arbitrary links

The submenu SHALL display a section for other links when the project has one or more labeled links.

#### Scenario: Links shown with label

- **GIVEN** a project has labeled links
- **WHEN** the submenu is open
- **THEN** each link is shown by its label

#### Scenario: Clicking a link opens it in the browser

- **WHEN** the user clicks a link item in the submenu
- **THEN** the link URL opens in the default browser

### Requirement: Submenu displays AI summary

The submenu SHALL display the project's cached AI summary at the bottom of the submenu. The summary is non-clickable.

#### Scenario: Summary is displayed when available

- **GIVEN** a project has a cached AI summary
- **WHEN** the submenu is open
- **THEN** the summary text is displayed, word-wrapped, at the bottom of the submenu

#### Scenario: Fallback when no summary is available

- **GIVEN** a project has no cached summary and no linked metadata
- **WHEN** the submenu is open
- **THEN** the submenu displays "No summary yet — attach GitHub issues or start an OpenSpec plan!"

#### Scenario: Summary updates without reopening the menu

- **GIVEN** the menu bar dropdown is closed and a new summary is generated in the background
- **WHEN** the user next opens the menu bar dropdown
- **THEN** the submenu reflects the updated summary
