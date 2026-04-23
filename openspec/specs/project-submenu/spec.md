# project-submenu Specification

## Purpose

Defines the per-project submenu attached to each row in the ProjectHub menu bar dropdown. The submenu surfaces the project's linked GitHub issues, PRs, arbitrary links, and AI-generated summary so the user can see at-a-glance context without leaving the menu, and can jump directly to any linked URL.

## Requirements

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

### Requirement: Open all links in browser

The submenu SHALL include an "Open All in Browser" item when the project has two or more total URLs (issues, PRs, and other links combined). Clicking it SHALL open all URLs as tabs in a single browser window.

#### Scenario: Open all links as browser tabs

- **GIVEN** a project has 3 linked URLs (1 issue, 1 PR, 1 Figma link)
- **WHEN** the user clicks "Open All in Browser" in the submenu
- **THEN** all 3 URLs open as tabs in the default browser using the array variant of `NSWorkspace.shared.open(_:withApplicationAt:configuration:)`

#### Scenario: Hidden when fewer than two links

- **GIVEN** a project has zero or one total URLs across issues, PRs, and links
- **WHEN** the submenu is open
- **THEN** the "Open All in Browser" item is not shown

#### Scenario: Separator placement

- **WHEN** the "Open All in Browser" item is shown
- **THEN** it appears below the link sections and above the AI summary, separated by dividers

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

### Requirement: Submenu displays project directory

The submenu SHALL display a "Directory" section positioned after the Issues and Pull Requests sections (and above Links, Open All, and AI Summary) when the project has a `path` assigned. The section SHALL consist of a non-clickable header labeled "Directory" and a clickable item showing the directory's basename, ellipsized to fit a reasonable width. The clickable item's tooltip SHALL show the full absolute path. Clicking the item SHALL copy the full absolute path to the system clipboard.

#### Scenario: Directory section appears when path is set

- **GIVEN** a project has a `path` assigned
- **WHEN** the user opens the submenu
- **THEN** a "Directory" section is shown in the submenu displaying the path's basename (ellipsized if long)

#### Scenario: Directory section is hidden when no path is set

- **GIVEN** a project has no `path` assigned
- **WHEN** the user opens the submenu
- **THEN** no "Directory" section is shown

#### Scenario: Clicking the directory item copies the full path

- **GIVEN** a project has `path` set to `/Users/alice/Development/my-project`
- **WHEN** the user clicks the directory item in the submenu
- **THEN** the system clipboard contains the string `/Users/alice/Development/my-project`

#### Scenario: Tooltip shows the full path

- **GIVEN** a project has a `path` whose basename is shown ellipsized
- **WHEN** the user hovers over the directory item
- **THEN** a tooltip shows the full absolute path

#### Scenario: Directory section ordering

- **GIVEN** a project has a `path` set and also has linked issues, PRs, and links
- **WHEN** the user opens the submenu
- **THEN** the "Directory" section appears after the Issues and Pull Requests sections and above the Links, Open All, and AI Summary sections
