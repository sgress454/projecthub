## MODIFIED Requirements

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

#### Scenario: Dismiss clears red to green

- **GIVEN** a project's state is `red`
- **WHEN** the user invokes the dismiss action for that project
- **THEN** the project's state becomes `green`

Rationale: red can fire while the user is already in the project's Space (e.g., a `Notification` for permission while the user is actively watching). The active-Space downgrade rule only fires on Space *change*, not on steady-state presence. Without a dismiss path, the user has to switch away and back just to clear the badge they've already seen. Dismiss remains explicit (a per-row × button, not the row click itself), so it cannot be triggered accidentally by clicking to switch Spaces.

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

### Requirement: Per-row dismiss control

Each project row SHALL display a dismiss control (a small "×" button or equivalent affordance) when its color state is `yellow` or `red`. Clicking the control SHALL invoke the dismiss action for that project and close the menu, without switching Spaces. The control SHALL be hidden when the color state is `green`.

#### Scenario: Dismiss control visible on yellow

- **GIVEN** a project's state is `yellow`
- **WHEN** the user opens the menu bar dropdown
- **THEN** the row shows a trailing dismiss control

#### Scenario: Dismiss control visible on red

- **GIVEN** a project's state is `red`
- **WHEN** the user opens the menu bar dropdown
- **THEN** the row shows a trailing dismiss control

#### Scenario: Dismiss control hidden on green

- **GIVEN** a project's state is `green`
- **WHEN** the user opens the menu bar dropdown
- **THEN** the row does NOT show a dismiss control

#### Scenario: Clicking dismiss does not switch Spaces

- **GIVEN** a project with an attention-demanding state is visible in the menu
- **WHEN** the user clicks the dismiss control
- **THEN** the project's state clears to green AND macOS does NOT switch to that project's Space AND the menu closes
