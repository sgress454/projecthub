## ADDED Requirements

### Requirement: Detect running Fleet processes

The app SHALL periodically scan running processes on the user's machine for Fleet-related commands and attribute each detected process to at most one configured project. The app SHALL recognize two process classes:

- **Fleet server**: a process whose executable path matches `*/build/fleet` and whose arguments include `serve`.
- **Webpack build**: a process whose command line invokes `webpack` (e.g. via `yarn ... webpack ...`) with `--progress` or `--watch`.

For each detected process, the app SHALL determine an "owning directory":
- For Fleet server: the process's current working directory.
- For Webpack: the parent directory of `--output <path>` if `--output` is present in the command line; otherwise the process's current working directory.

The app SHALL attribute the process to the configured project whose `path` is the longest prefix of the owning directory. If no project's `path` is a prefix of the owning directory, the process SHALL NOT be attributed to any project.

The app SHALL refresh the scan on a recurring interval while the menu bar list is visible or being kept current; the interval SHALL be short enough to feel responsive (a few seconds) and SHALL be implemented using macOS `libproc` rather than shelling out.

#### Scenario: Fleet server attributed to a project by cwd

- **GIVEN** project "api" has `path` = `/Users/scott/code/api`
- **AND** a process with executable path `/Users/scott/code/api/build/fleet` and arguments `serve` is running with cwd `/Users/scott/code/api`
- **WHEN** the menu bar list is rendered
- **THEN** the api project's row shows a 🌐 indicator

#### Scenario: Webpack attributed by --output across projects

- **GIVEN** project "server" has `path` = `/Users/scott/code/server`
- **AND** project "frontend" has `path` = `/Users/scott/code/frontend`
- **AND** a process running `yarn run webpack --progress --output /Users/scott/code/server/server/assets` was launched with cwd `/Users/scott/code/frontend`
- **WHEN** the menu bar list is rendered
- **THEN** the server project's row shows a 🎨 indicator
- **AND** the frontend project's row does NOT show a 🎨 indicator

#### Scenario: Webpack without --output falls back to cwd

- **GIVEN** project "frontend" has `path` = `/Users/scott/code/frontend`
- **AND** a process running `yarn run webpack --watch` is running with cwd `/Users/scott/code/frontend`
- **WHEN** the menu bar list is rendered
- **THEN** the frontend project's row shows a 🎨 indicator

#### Scenario: Process whose path matches no project is ignored

- **GIVEN** no configured project's `path` is a prefix of `/tmp/scratch`
- **AND** `fleet serve` is running with cwd `/tmp/scratch`
- **WHEN** the menu bar list is rendered
- **THEN** no project's row shows a 🌐 indicator

#### Scenario: Most-specific project wins

- **GIVEN** project "monorepo" has `path` = `/Users/scott/code/monorepo`
- **AND** project "monorepo-fleet" has `path` = `/Users/scott/code/monorepo/fleet`
- **AND** `fleet serve` is running with cwd `/Users/scott/code/monorepo/fleet`
- **WHEN** the menu bar list is rendered
- **THEN** the monorepo-fleet project's row shows the 🌐 indicator
- **AND** the monorepo project's row does NOT show the 🌐 indicator

### Requirement: Render process indicators in menu bar rows

The app SHALL render a 🌐 indicator on a project's menu bar row when a Fleet server is currently attributed to that project, and a 🎨 indicator when a webpack build is currently attributed to that project. Indicators SHALL be right-aligned next to the existing terminal icon. When a process is no longer detected, the corresponding indicator SHALL disappear from that project's row on the next refresh.

#### Scenario: Indicators appear when processes are detected

- **GIVEN** project "api" has both a Fleet server and a webpack build attributed to it
- **WHEN** the menu bar list is rendered
- **THEN** the api row shows both 🌐 and 🎨, right-aligned next to the terminal icon

#### Scenario: Indicators disappear when processes stop

- **GIVEN** project "api" was previously showing a 🌐 indicator
- **WHEN** the Fleet server process exits and the next scan completes
- **THEN** the api row no longer shows a 🌐 indicator

#### Scenario: Projects with no detected processes show no indicators

- **GIVEN** project "docs" has no Fleet or webpack processes attributed to it
- **WHEN** the menu bar list is rendered
- **THEN** the docs row shows neither 🌐 nor 🎨

### Requirement: Hover detail for process indicators

The app SHALL surface contextual detail on hover for each indicator:

- 🌐 (Fleet server): the TCP port the server is listening on, derived from the server's command-line arguments or by querying the process's listening sockets.
- 🎨 (Webpack): the absolute path of the `--output` directory if `--output` was supplied, otherwise the absolute path of the project's directory.

If the port cannot be determined for a 🌐 indicator, the hover detail SHALL fall back to a neutral string (e.g. "Fleet server running") rather than displaying nothing or an error.

#### Scenario: Hover on backend indicator shows port

- **GIVEN** project "api" has a Fleet server attributed to it that is listening on port 8080
- **WHEN** the user hovers over the 🌐 indicator on the api row
- **THEN** a tooltip displays "port 8080" (or equivalent)

#### Scenario: Hover on frontend indicator shows --output dir

- **GIVEN** project "server" has a webpack build attributed to it whose `--output` is `/Users/scott/code/server/server/assets`
- **WHEN** the user hovers over the 🎨 indicator on the server row
- **THEN** a tooltip displays `/Users/scott/code/server/server/assets`

#### Scenario: Hover on frontend indicator without --output shows project dir

- **GIVEN** project "frontend" has a webpack build attributed to it whose command line has no `--output`
- **AND** project "frontend" has `path` = `/Users/scott/code/frontend`
- **WHEN** the user hovers over the 🎨 indicator on the frontend row
- **THEN** a tooltip displays `/Users/scott/code/frontend`

#### Scenario: Port undetermined falls back gracefully

- **GIVEN** project "api" has a Fleet server attributed to it but the port cannot be determined
- **WHEN** the user hovers over the 🌐 indicator on the api row
- **THEN** a tooltip displays a neutral string indicating the server is running, with no error

### Requirement: Click on indicator summons iTerm hotkey window

The app SHALL summon the user's iTerm hotkey window when either the 🌐 or 🎨 indicator is clicked, by posting the keystroke configured in the `iTerm hotkey-window keystroke` app preference. The click SHALL NOT trigger the row's existing Space-switch behavior.

If no iTerm hotkey-window keystroke is configured, clicking an indicator SHALL surface a dialog explaining that the keystroke is unset and offering to open the Preferences modal, rather than silently doing nothing or posting an arbitrary keypress.

#### Scenario: Clicking indicator posts the configured keystroke

- **GIVEN** the user has configured the iTerm hotkey-window keystroke as `⌃⌥⌘T`
- **WHEN** the user clicks the 🌐 indicator on a project row
- **THEN** the app posts a `Control+Option+Command+T` keystroke
- **AND** the app does NOT switch macOS to the project's assigned Space

#### Scenario: Clicking indicator without configured keystroke

- **GIVEN** the user has not configured the iTerm hotkey-window keystroke
- **WHEN** the user clicks the 🎨 indicator on a project row
- **THEN** the app shows a dialog explaining that the keystroke is unset
- **AND** the dialog offers a button to open the Preferences modal

#### Scenario: Clicking the row itself still switches Space

- **GIVEN** a project row shows a 🌐 indicator
- **WHEN** the user clicks the row outside of the indicator
- **THEN** the app switches to the project's assigned Space (existing behavior)
- **AND** does NOT post the iTerm hotkey-window keystroke
