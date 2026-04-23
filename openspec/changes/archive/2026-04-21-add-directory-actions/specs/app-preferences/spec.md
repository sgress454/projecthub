## ADDED Requirements

### Requirement: Persisted app preferences store

The app SHALL persist user-level preferences to `~/Library/Application Support/ProjectHub/preferences.json`. The file SHALL use a versioned JSON object (`version: 1`) and SHALL round-trip unknown fields, consistent with the app's existing storage idiom.

#### Scenario: Preferences survive app restart

- **GIVEN** the user has set a preference value via the Preferences modal
- **WHEN** the user quits and relaunches the app
- **THEN** the preference value is restored from `preferences.json`

#### Scenario: First launch without a preferences file

- **WHEN** the app launches and `preferences.json` does not exist
- **THEN** the app uses default values and does not raise an error

#### Scenario: Unknown fields are preserved

- **GIVEN** `preferences.json` contains fields not defined by the current schema
- **WHEN** the app saves the file after an edit
- **THEN** those unknown fields are preserved on disk

### Requirement: Terminal application preference

The app SHALL store the user's chosen terminal application as a string identifier in preferences. Supported values are `"iterm2"` (iTerm2) and `"terminal"` (macOS Terminal.app). The preference SHALL default, on first launch only, to `"iterm2"` if iTerm2 is installed on the system, otherwise to `"terminal"`.

#### Scenario: Default when iTerm2 is installed

- **GIVEN** iTerm2 is installed (bundle identifier `com.googlecode.iterm2` resolvable) and no preferences file exists
- **WHEN** the app launches
- **THEN** the effective terminal preference is `"iterm2"` and is persisted to `preferences.json`

#### Scenario: Default when iTerm2 is not installed

- **GIVEN** iTerm2 is not installed and no preferences file exists
- **WHEN** the app launches
- **THEN** the effective terminal preference is `"terminal"` and is persisted to `preferences.json`

#### Scenario: Persisted value is not re-detected on launch

- **GIVEN** `preferences.json` already contains a terminal preference value
- **WHEN** the app launches
- **THEN** the persisted value is used verbatim, regardless of which terminals are currently installed

### Requirement: Preferences modal

The app SHALL provide a Preferences modal that exposes editable preferences. The modal SHALL be reachable from (a) the status-item right-click context menu and (b) a control in the Edit Projects window. Changes SHALL be saved immediately on edit (no explicit Save button).

#### Scenario: Opening Preferences from the status item

- **WHEN** the user right-clicks the menu bar icon and selects "Preferences…"
- **THEN** the Preferences modal appears

#### Scenario: Opening Preferences from Edit Projects

- **WHEN** the user clicks the "Preferences…" control in the Edit Projects window
- **THEN** the Preferences modal appears

#### Scenario: Changing terminal selection is immediate

- **WHEN** the user selects a different terminal application in the Preferences modal
- **THEN** the new value is written to `preferences.json` and applied to subsequent terminal-launch actions without requiring the modal to be closed first

### Requirement: Open directory in configured terminal

The app SHALL open a given directory in the user's configured terminal application via `NSWorkspace` by resolving the terminal's bundle identifier to an app URL and opening the directory URL with that app.

#### Scenario: Directory opens in iTerm2

- **GIVEN** the terminal preference is `"iterm2"` and iTerm2 is installed
- **WHEN** the app is asked to open a directory
- **THEN** iTerm2 opens with a shell session rooted at that directory

#### Scenario: Directory opens in Terminal.app

- **GIVEN** the terminal preference is `"terminal"` and Terminal.app is available
- **WHEN** the app is asked to open a directory
- **THEN** Terminal.app opens with a shell session rooted at that directory

#### Scenario: Configured terminal is not installed

- **GIVEN** the terminal preference names an application whose bundle identifier is not resolvable on the system
- **WHEN** the app would launch the terminal
- **THEN** the launch is skipped, a warning is logged, and the UI surface that triggered it reflects an unavailable state (e.g., disabled control with explanatory tooltip)
