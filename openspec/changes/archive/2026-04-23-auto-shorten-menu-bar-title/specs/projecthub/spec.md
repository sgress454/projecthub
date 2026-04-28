## ADDED Requirements

### Requirement: Adaptive menu bar title rendering

When the "Show project name in menu bar" preference is enabled and an active project is identified for the current Space, the app SHALL render the status-item label in the longest form that still fits within the available menu bar width without causing the system to hide the status item. The three forms, in descending preference, SHALL be: (a) the full project name, (b) the project name truncated at the end with a trailing ellipsis (`…`), (c) icon-only (no title text). The app SHALL fall back through these forms automatically; the status item SHALL always render at least the icon (form c) and SHALL NOT be hidden solely because its title was too long.

The app SHALL re-evaluate the chosen form whenever any of the following occur: the active project changes, the active project's name is edited, the menu bar's available width changes (screen configuration change, notch/safe-area change, full-screen app enters or exits), or the status item's hosting window reports a change in occlusion state.

When the "Show project name in menu bar" preference is disabled, the app SHALL render icon-only regardless of available width.

#### Scenario: Full name fits

- **GIVEN** the "Show project name in menu bar" preference is enabled and the active project is `"api-refactor"`
- **AND** the menu bar has enough free width to display `" api-refactor"` alongside other status items
- **WHEN** the app renders the status-item label
- **THEN** the label displays the full project name `"api-refactor"`

#### Scenario: Name is truncated to fit

- **GIVEN** the preference is enabled and the active project is `"very-long-project-name-that-overflows"`
- **AND** the menu bar does not have enough width for the full name but has width for a shorter string
- **WHEN** the app renders the status-item label
- **THEN** the label displays the project name shortened at the end with a trailing `…`, at the longest length that fits

#### Scenario: Falls back to icon-only when even truncated title does not fit

- **GIVEN** the preference is enabled and the available width is too narrow for any meaningful truncated name
- **WHEN** the app renders the status-item label
- **THEN** the label is empty and the status item shows only its icon
- **AND** the status item is not hidden

#### Scenario: Re-evaluates when screen configuration changes

- **GIVEN** the app is rendering a truncated title because an external display with a wide menu bar is connected
- **WHEN** the external display is disconnected and the main display has a notch
- **THEN** the app re-evaluates and shortens the title further (or falls back to icon-only) so the status item remains visible

#### Scenario: Re-evaluates when active project changes

- **GIVEN** the current active project name fits in full
- **WHEN** the user switches to a Space whose active project has a longer name
- **THEN** the app re-evaluates and truncates (or falls back to icon-only) so the new name does not cause the item to be hidden

#### Scenario: Preference disabled forces icon-only

- **GIVEN** the "Show project name in menu bar" preference is disabled
- **WHEN** the app renders the status-item label
- **THEN** the label is empty regardless of available width or active project
