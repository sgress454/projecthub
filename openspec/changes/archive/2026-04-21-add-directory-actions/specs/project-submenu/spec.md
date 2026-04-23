## ADDED Requirements

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
