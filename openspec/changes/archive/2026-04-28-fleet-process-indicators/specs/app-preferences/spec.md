## ADDED Requirements

### Requirement: iTerm hotkey-window keystroke preference

The app SHALL persist a user-configurable keystroke representing the global hotkey the user has bound in iTerm2 to summon their hotkey window. The preference SHALL be stored in `preferences.json` as a structured representation of the keystroke (modifier mask plus key code) sufficient to be replayed via a `CGEvent` keypress. The preference SHALL be optional — if unset, no keystroke is posted by features that depend on it.

The Preferences modal SHALL provide a control allowing the user to capture the keystroke (e.g. by pressing the desired chord while a "Record shortcut" control is focused), display the currently captured chord, and clear it.

#### Scenario: Setting the keystroke survives restart

- **GIVEN** the user opens Preferences and records `⌃⌥⌘T` for the iTerm hotkey-window keystroke
- **WHEN** the user quits and relaunches the app
- **THEN** the preference still records `⌃⌥⌘T`

#### Scenario: Unset preference produces no keypress

- **GIVEN** the user has not configured the iTerm hotkey-window keystroke
- **WHEN** any feature requests the keystroke be posted
- **THEN** no keypress is posted
- **AND** the requesting feature SHALL handle the unset case (e.g. surface a dialog directing the user to Preferences)

#### Scenario: Clearing the keystroke

- **GIVEN** the user has previously configured `⌃⌥⌘T`
- **WHEN** the user clears the field in Preferences
- **THEN** the preference returns to unset
- **AND** subsequent feature requests behave as if the preference had never been set
