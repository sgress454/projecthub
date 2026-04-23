## ADDED Requirements

### Requirement: Per-row open-in-terminal control

Each project row in the menu bar dropdown SHALL display a trailing "open in terminal" control (an icon button). When clicked for a project that has a `path` assigned and the configured terminal application is available, the control SHALL open that directory in the configured terminal application and close the menu without switching Spaces. The control SHALL be shown in a visually disabled (greyed) state when the project has no `path` assigned, serving as a visual indicator that a directory is not set.

#### Scenario: Control is enabled when path is set

- **GIVEN** a project has a `path` assigned and the configured terminal application is resolvable
- **WHEN** the user opens the menu bar dropdown
- **THEN** the row shows a trailing terminal-icon control rendered in its enabled state

#### Scenario: Control is disabled when no path is set

- **GIVEN** a project has no `path` assigned
- **WHEN** the user opens the menu bar dropdown
- **THEN** the row shows a trailing terminal-icon control rendered in a greyed, disabled state, and clicking it has no effect

#### Scenario: Control is disabled when configured terminal is not installed

- **GIVEN** a project has a `path` assigned but the configured terminal application's bundle identifier cannot be resolved on the system
- **WHEN** the user opens the menu bar dropdown
- **THEN** the row shows the trailing control in a greyed, disabled state, and its tooltip indicates that the configured terminal is not installed

#### Scenario: Clicking the control opens the directory in the terminal

- **GIVEN** a project has a `path` assigned and the configured terminal is available
- **WHEN** the user clicks the trailing terminal control
- **THEN** the configured terminal application opens with a shell session rooted at the project's directory AND macOS does NOT switch to that project's Space AND the menu closes

#### Scenario: Clicking the control does not switch Spaces

- **GIVEN** a project is assigned to a Space other than the current one
- **WHEN** the user clicks the trailing terminal control on that project's row
- **THEN** the active Space is unchanged
