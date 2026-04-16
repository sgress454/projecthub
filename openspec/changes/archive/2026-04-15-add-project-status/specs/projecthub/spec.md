## ADDED Requirements

### Requirement: Per-project Claude state tracking

The app SHALL track a state per project that reflects Claude's current need for the user. The state takes exactly one of the values `green` (nothing pending), `yellow` (begs for attention), or `red` (Claude is waiting on the user). The app SHALL also track a `working` sub-state that indicates Claude is mid-turn for that project; `working` can be true simultaneously with any color value.

State transitions SHALL occur only in response to explicit triggers. The app SHALL NOT change a project's state on a timer, on idle, or through any other implicit decay.

#### Scenario: Notification event sets state to red

- **GIVEN** a project has `claude_enabled` set to true
- **WHEN** a Claude Code `Notification` event is ingested whose cwd matches this project
- **THEN** the project's state becomes `red`

#### Scenario: Stop event classified as QUESTION sets state to red

- **GIVEN** a project has `claude_enabled` set to true
- **WHEN** a `Stop` event is ingested whose cwd matches this project and the classifier returns `QUESTION`
- **THEN** the project's state becomes `red`

#### Scenario: Stop event classified as REPORT sets state to yellow

- **GIVEN** a project has `claude_enabled` set to true
- **WHEN** a `Stop` event is ingested whose cwd matches this project and the classifier returns `REPORT`
- **THEN** the project's state becomes `yellow`

#### Scenario: Stop event classified as DONE sets state to green

- **GIVEN** a project has `claude_enabled` set to true
- **WHEN** a `Stop` event is ingested whose cwd matches this project and the classifier returns `DONE`
- **THEN** the project's state becomes `green`

#### Scenario: UserPromptSubmit clears state to green and enters working

- **GIVEN** a project has `claude_enabled` set to true and state `red`, `yellow`, or `green`
- **WHEN** a `UserPromptSubmit` event is ingested whose cwd matches this project
- **THEN** the project's state becomes `green` AND the `working` sub-state becomes true

#### Scenario: PreToolUse clears red immediately on permission approval

- **GIVEN** a project's state is `red` from a permission `Notification`
- **WHEN** the user approves the permission and a `PreToolUse` event is ingested for this project
- **THEN** the project's color state becomes `green` AND the `working` sub-state becomes true

Rationale: PreToolUse fires after permission is granted and just before tool execution. This is the earliest signal that the user is no longer blocking; without it the red stays stuck until the tool finishes (PostToolUse), which can be several seconds for slow tools.

#### Scenario: PostToolUse clears attention state to green and keeps working

- **GIVEN** a project has `claude_enabled` set to true
- **WHEN** a `PostToolUse` event is ingested whose cwd matches this project
- **THEN** the project's color state becomes `green` AND the `working` sub-state becomes true

#### Scenario: Stop ends the working sub-state

- **GIVEN** a project has `working` set to true
- **WHEN** any `Stop` event is ingested whose cwd matches this project
- **THEN** `working` becomes false (the color state is updated by the classifier per the Stop scenarios above)

#### Scenario: Active Space becoming this project downgrades red to yellow

- **GIVEN** a project's state is `red`
- **WHEN** macOS reports via `NSWorkspace.activeSpaceDidChangeNotification` that the active Space is now this project's assigned Space
- **THEN** the project's state becomes `yellow`

#### Scenario: Dismiss clears yellow to green without a Claude reply

- **GIVEN** a project's state is `yellow`
- **WHEN** the user invokes the dismiss action for that project
- **THEN** the project's state becomes `green`

#### Scenario: Dismiss is a no-op on red

- **GIVEN** a project's state is `red`
- **WHEN** the user invokes the dismiss action for that project
- **THEN** the project's state remains `red`

Rationale: red means Claude is genuinely waiting on the user. Dismissing it would hide a real block — the user must either respond to Claude (UserPromptSubmit) or let Claude's next tool-use clear it (PreToolUse / PostToolUse).

#### Scenario: Dismiss is a no-op on green

- **GIVEN** a project's state is `green`
- **WHEN** the user invokes the dismiss action for that project
- **THEN** the project's state remains `green`

#### Scenario: Active Space change leaves non-red states unchanged

- **GIVEN** a project's state is `green` or `yellow`
- **WHEN** macOS reports that the active Space is now this project's assigned Space
- **THEN** the project's state is unchanged

#### Scenario: State persists across app restart via event replay

- **GIVEN** ProjectHub is relaunched after a previous session
- **WHEN** the app initializes
- **THEN** it replays recent events from `events.jsonl` to reconstruct each project's last-known state before showing the menu bar dropdown

### Requirement: Per-project Claude monitoring opt-in

Each project SHALL have an optional boolean field `claude_enabled` (default `false`). When `claude_enabled` is `false`, the app SHALL NOT change that project's state in response to any hook event, and the project's row SHALL render as `green` with no `working` sub-state regardless of ingested events.

#### Scenario: Disabled project ignores Claude events

- **GIVEN** a project whose `claude_enabled` is false
- **WHEN** any hook event with a matching cwd is ingested
- **THEN** the project's state remains `green` and `working` remains false

#### Scenario: Enabling monitoring without a path has no effect

- **GIVEN** a project has `claude_enabled` set to true but no `path`
- **WHEN** any hook event is ingested
- **THEN** no hook event matches this project and its state remains `green`

#### Scenario: Enabling monitoring activates state updates

- **GIVEN** a project has both `path` set and `claude_enabled` set to true
- **WHEN** a matching hook event is ingested
- **THEN** the project's state is updated according to the transition rules

### Requirement: Project filesystem path field

Each project SHALL have an optional `path` field identifying the filesystem directory associated with the project. The app SHALL provide a directory picker for setting this field in the Edit Projects window.

#### Scenario: Path is persisted alongside name and space

- **WHEN** the user sets a project's path and the store is saved
- **THEN** reloading the store returns the same path on that project

#### Scenario: Editing path uses a directory picker

- **WHEN** the user invokes the path edit control on a project row in the Edit Projects window
- **THEN** a macOS directory-selection dialog is presented and the chosen directory populates the `path` field

#### Scenario: v0.1 files load without path

- **GIVEN** a `projects.json` file written by v0.1 (containing only `name` and `space` per project)
- **WHEN** the app reads the file
- **THEN** each project loads with `path` absent and `claude_enabled` defaulting to false, and no error is raised

### Requirement: Claude Code hook installation

The app SHALL provide an opt-in install flow that adds a ProjectHub-managed hook to `~/.claude/settings.json` for the `Stop`, `Notification`, `UserPromptSubmit`, and `PostToolUse` events. The app SHALL provide a matching uninstall flow that removes only the entries it added, leaving any other user-defined hooks intact.

The install and uninstall flows SHALL require explicit user confirmation that displays the changes to be made before they are written.

#### Scenario: Install flow shows a preview before writing

- **WHEN** the user clicks "Enable Claude status" in the Edit Projects window
- **THEN** the app displays a preview of the changes to `~/.claude/settings.json` and does not write the file until the user confirms

#### Scenario: Install preserves existing user hooks

- **GIVEN** `~/.claude/settings.json` already contains the user's own hook entries
- **WHEN** the user confirms installation of ProjectHub's hook
- **THEN** the file is updated to include ProjectHub's four hook entries AND the user's existing hook entries remain unchanged

#### Scenario: Uninstall removes only ProjectHub entries

- **GIVEN** ProjectHub's hook is installed and the user has additional hooks of their own
- **WHEN** the user disables Claude status
- **THEN** only the ProjectHub-tagged hook entries are removed and any other hooks are preserved

#### Scenario: Installed hook script never interferes with Claude

- **WHEN** the installed hook script runs, regardless of whether it succeeds or fails
- **THEN** it produces no output on stdout or stderr visible to Claude, and it exits without blocking the originating Claude session

#### Scenario: Install is reversible

- **GIVEN** Claude status has been enabled
- **WHEN** the user disables Claude status and then re-enables it later
- **THEN** `~/.claude/settings.json` returns to its fully-installed form and the app resumes ingesting events

### Requirement: Hook event ingestion

The app SHALL watch `~/Library/Application Support/ProjectHub/events.jsonl` for appended lines and SHALL process each line as a hook event. Each event is associated with a project by matching the event's `cwd` field against project `path` fields and selecting the project whose `path` is the longest prefix of the `cwd`.

#### Scenario: New event updates project state in real time

- **GIVEN** the user has an enabled project with `path` set and the app is running
- **WHEN** the hook script appends a new event line whose cwd is inside the project's path
- **THEN** the app detects the append, parses the event, and applies the state transition for that project without requiring user interaction

#### Scenario: Longest-prefix matching resolves worktrees

- **GIVEN** two projects A with `path` `/Users/x/repo` and B with `path` `/Users/x/repo/worktrees/feature`
- **WHEN** an event with cwd `/Users/x/repo/worktrees/feature/src` is ingested
- **THEN** the event is matched to project B

#### Scenario: Events without a matching project are ignored

- **WHEN** an event is ingested whose cwd is not a descendant of any project's `path`
- **THEN** the event is discarded without changing any project's state

#### Scenario: Malformed event lines are skipped

- **WHEN** an event line is ingested that is not valid JSON or is missing required fields
- **THEN** the line is skipped with a logged warning and subsequent lines continue to be processed

### Requirement: Stop-event classification

The app SHALL classify every `Stop` event for an enabled project into one of `QUESTION`, `REPORT`, or `DONE` using a deterministic prompt sent to a subprocess invocation of the `claude` CLI. The resulting category maps directly to the state transitions defined in "Per-project Claude state tracking."

#### Scenario: Classifier is invoked with the final assistant message

- **WHEN** a `Stop` event is received for an enabled project
- **THEN** the app reads the final assistant message from the event's transcript and invokes `claude -p` with the classification prompt and that message

#### Scenario: Classifier output is mapped to state

- **WHEN** `claude -p` returns exactly `QUESTION`, `REPORT`, or `DONE`
- **THEN** the project's state becomes `red`, `yellow`, or `green` respectively

#### Scenario: Classifier defaults to red on failure

- **WHEN** `claude -p` exits non-zero, times out (>3 seconds), returns output that is not one of the three tokens, or is not installed on `PATH`
- **THEN** the project's state becomes `red` and a warning is logged

#### Scenario: Classifier runs asynchronously

- **WHEN** a `Stop` event arrives for an enabled project
- **THEN** the row's current state is preserved until the classifier resolves, and no intermediate placeholder state is displayed

### Requirement: Per-row status indicator

Each project row in the menu bar dropdown SHALL display a leading status indicator reflecting that project's current state. A green, yellow, or red filled circle SHALL represent the corresponding color state. A spinning progress indicator SHALL replace the circle when the project is in the `working` sub-state.

#### Scenario: Indicator reflects color state

- **GIVEN** a project's state is `red`
- **WHEN** the user opens the menu bar dropdown
- **THEN** the project's row displays a red filled circle as its leading indicator

#### Scenario: Working state shows a spinner

- **GIVEN** a project is in the `working` sub-state
- **WHEN** the user opens the menu bar dropdown
- **THEN** the project's row displays a spinning progress indicator in place of the colored circle

#### Scenario: Disabled project shows green indicator

- **GIVEN** a project's `claude_enabled` is false
- **WHEN** the user opens the menu bar dropdown
- **THEN** the project's row displays a green indicator regardless of any events ingested for its path

### Requirement: Per-row dismiss control

Each project row SHALL display a dismiss control (a small "×" button or equivalent affordance) when its color state is `yellow`. Clicking the control SHALL invoke the dismiss action for that project and close the menu, without switching Spaces. The control SHALL be hidden when the color state is `green` or `red`.

#### Scenario: Dismiss control visible on yellow

- **GIVEN** a project's state is `yellow`
- **WHEN** the user opens the menu bar dropdown
- **THEN** the row shows a trailing dismiss control

#### Scenario: Dismiss control hidden on non-yellow

- **GIVEN** a project's state is `green` or `red`
- **WHEN** the user opens the menu bar dropdown
- **THEN** the row does NOT show a dismiss control

#### Scenario: Clicking dismiss does not switch Spaces

- **GIVEN** a yellow project is visible in the menu
- **WHEN** the user clicks the dismiss control
- **THEN** the project's state clears to green AND macOS does NOT switch to that project's Space AND the menu closes

### Requirement: Menu bar icon badge

The menu bar icon SHALL display a numeric badge equal to the count of projects whose state is `red` or `yellow`. The badge SHALL be hidden when that count is zero. The badge SHALL be tinted red when at least one project is `red`; otherwise it SHALL be tinted yellow. Projects in the `working` sub-state SHALL NOT contribute to the badge count unless their color state is also red or yellow.

#### Scenario: Badge sums red and yellow counts

- **GIVEN** two projects are `red` and one is `yellow`
- **WHEN** the user observes the menu bar
- **THEN** the badge displays `3`

#### Scenario: Badge uses red tint when any project is red

- **GIVEN** at least one project is `red`
- **WHEN** the user observes the menu bar badge
- **THEN** it is rendered with the red tint regardless of how many yellow projects exist

#### Scenario: Badge uses yellow tint when only yellow projects exist

- **GIVEN** no project is `red` and at least one is `yellow`
- **WHEN** the user observes the menu bar badge
- **THEN** it is rendered with the yellow tint

#### Scenario: Badge is hidden when all projects are green

- **GIVEN** no project is `red` or `yellow`
- **WHEN** the user observes the menu bar
- **THEN** no badge is displayed next to the icon

#### Scenario: Working alone does not show in badge

- **GIVEN** a project is in `working` sub-state and its color state is `green`
- **WHEN** the user observes the menu bar
- **THEN** no badge is displayed on account of that project

#### Scenario: Menu bar icon pulses while any project is working

- **GIVEN** at least one project is in the `working` sub-state
- **WHEN** the user observes the menu bar icon
- **THEN** the icon animates with a subtle opacity pulse

#### Scenario: Icon animation stops when no projects are working

- **GIVEN** no project is in the `working` sub-state
- **WHEN** the user observes the menu bar icon
- **THEN** the icon is rendered at full opacity with no animation

### Requirement: Edit Projects window extended for status monitoring

The Edit Projects window SHALL provide controls for editing each project's `path` and `claude_enabled` fields, and a global control for installing or uninstalling the Claude Code hook.

#### Scenario: Path editing control per row

- **WHEN** the user views a project row in the Edit Projects window
- **THEN** the row exposes a control that opens a directory picker and writes the chosen directory to the project's `path`

#### Scenario: Claude toggle per row

- **WHEN** the user views a project row in the Edit Projects window
- **THEN** the row exposes a toggle that sets `claude_enabled` and is disabled (cannot be turned on) if `path` is empty

#### Scenario: Global hook install toggle

- **WHEN** the user views the Edit Projects window
- **THEN** a global "Enable Claude status" control is visible that reflects and toggles the installed state of the hook in `~/.claude/settings.json`

#### Scenario: Warning when `claude` CLI is not on PATH

- **GIVEN** the `claude` CLI is not found on the user's `PATH`
- **WHEN** the user opens the Edit Projects window
- **THEN** an inline warning is displayed explaining that classification will default to red

### Requirement: Storage schema version 2

The app SHALL write `projects.json` with `version` set to `2`, SHALL preserve existing v1 files on read without requiring migration, and SHALL continue to round-trip unknown fields per the v0.1 forward-compatibility guarantee.

#### Scenario: New files are written with version 2

- **WHEN** the app saves the store after any edit
- **THEN** the written file has `"version": 2` at the top level

#### Scenario: Version 1 files load without error

- **GIVEN** a `projects.json` file with `"version": 1`
- **WHEN** the app starts
- **THEN** the file loads successfully, all projects are available, and `claude_enabled` is false on every project

#### Scenario: Unknown fields are preserved

- **GIVEN** a `projects.json` file contains fields not defined by the current schema
- **WHEN** the app saves the file after an edit
- **THEN** those unknown fields are preserved on disk
