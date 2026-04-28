## MODIFIED Requirements

### Requirement: Menu bar project list

The app SHALL show the project list in a macOS menu bar dropdown with each project's name visible at a glance. The assigned Space number SHALL NOT be displayed in the menu bar row; it remains visible and editable in the Edit Projects window.

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
