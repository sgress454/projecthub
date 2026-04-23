# Changelog

## Unreleased — Directory actions

### Added

- Adaptive menu-bar title: the active project name now shortens to the longest form that fits the available menu-bar width, falling back to icon-only before the system would otherwise hide the status item entirely. Re-evaluates on screen configuration changes, notch appearance, and occlusion-state notifications (debounced).
- Submenu "Directory" section in each project submenu (positioned after Issues and PRs) when a directory is assigned. Shows the ellipsized folder name; clicking copies the full absolute path to the clipboard. Tooltip shows the full path.
- Trailing terminal icon pinned to the far-right edge of each main-menu project row. Enabled when the project has a path and the configured terminal is installed; greyed out otherwise — doubling as a visual cue for projects missing a folder. Clicking opens the project directory in the configured terminal without switching Spaces.
- Preferences window with a terminal-application picker (iTerm2 / Terminal.app). Reachable from the menu's "Preferences…" item and from the Edit Projects window. Defaults, on first launch only, to iTerm2 if installed, otherwise Terminal.app. Persisted to `~/Library/Application Support/ProjectHub/preferences.json`.
- Space picker in the Edit Projects window now offers 1–16 (was 1–9). Spaces 10–12 use `Control+0`, `Control+-`, `Control+=` by convention; 13–16 require a user-assigned shortcut.
- Clicking a project row whose "Switch to Desktop N" shortcut is not enabled in System Settings now shows an actionable dialog that deep-links to the Keyboard Shortcuts pane, instead of silently producing the macOS error beep.
- Edit Projects window renders sorted ascending by Space number on each open. Rows don't reshuffle while the window is open; on-disk project order is untouched.

## v0.2.1 — Dismiss red

Small follow-up: dismiss now clears red as well as yellow. Real use surfaced the case where red fires while you're already in the project's Space (the active-Space downgrade fires only on Space change, not steady-state presence), which previously stranded red until you switched away and back.

### Changed

- `StatusCoordinator.dismiss(projectId:)` clears `red` OR `yellow` to `green` (was yellow-only).
- The per-row × dismiss button now appears on both red and yellow rows (previously yellow-only). Still hidden on green. Still distinct from the row click that switches Spaces, so accidents are avoided.

## v0.2 — Claude status

Adds per-project Claude Code state monitoring. Opt-in; v0.1 users see no behavioral change until they enable it.

### Added

- Per-project `🟢` / `🟡` / `🔴` traffic-light state driven by Claude Code hook events (`Stop`, `Notification`, `UserPromptSubmit`, `PostToolUse`).
- `⏳` working sub-state — a small `NSProgressIndicator` spinner while Claude is mid-turn.
- Menu bar icon badge showing the count of red + yellow projects; tinted red if any project is red, yellow otherwise.
- Three-way classifier for Stop events (QUESTION / REPORT / DONE) via a `claude -p` subprocess. `.failure` (no CLI, timeout, unparseable output) defaults to red.
- Opt-in per-project `path` (directory picker) and `claudeEnabled` toggle.
- Global "Enable Claude status" toggle in the Edit Projects window, with preview of changes to `~/.claude/settings.json` before writing. Reversible; preserves user's existing hooks.
- Startup replay of `events.jsonl` to reconstruct state after a restart.
- Log rotation at 10 MB, keeps 3 rotated files.
- Active-Space observation downgrades red → yellow via the existing `activeSpaceDidChangeNotification` observer.
- `PreToolUse` + `PostToolUse` both clear to green (with working=true). A permission prompt that the user approves mid-turn therefore removes the project from the badge as soon as the user clicks approve (via `PreToolUse`) — the spinner still shows in the menu but nothing is demanding attention.
- Per-row "×" dismiss button on yellow rows. Clears the yellow to green without requiring a new Claude prompt. Only shown on yellow (red remains undismissible; Claude is genuinely waiting there).
- Menu bar icon pulses (~1 s breathing animation) whenever any project is in the `working` sub-state. Gives an ambient "Claude is doing something somewhere" signal without stealing attention.
- Warning banners in the editor when `claude` CLI isn't on `PATH`, or when the installed hook has been hand-edited away from the expected command.
- Refactor: pure logic extracted to a `ProjectHubKit` library target with its own test suite (74 tests).

### Changed

- `projects.json` schema is now `version: 2`. v0.1 files load unchanged; new fields (`path`, `claude_enabled`, `settings.claude_hook_installed`) are optional and default to absent / false.
- Menu rows now use custom views (instead of `attributedTitle` with tab stops) so the working spinner can actually animate.

### Notes

- **Privacy:** when classification runs, the final assistant message from the Claude transcript is sent to `claude -p` through your existing Claude auth. No other network activity.
- **Dependency (optional):** the `claude` CLI on `$PATH`. Without it, Stop events for enabled projects default to red.

## v0.1 — Alpha

Initial release. Provides the smallest useful unit: labeled project-to-Space mapping and one-click Space switching.

### Added

- Menu bar app (AppKit `NSStatusItem`) showing a list of projects with their Space numbers.
- Click-to-switch: clicking a project posts a synthesized `Ctrl+N` keystroke to switch macOS Spaces.
- Edit Projects window (SwiftUI) with add, remove, rename, and Space reassignment.
- Persistent storage in `~/Library/Application Support/ProjectHub/projects.json`, forward-compatible with future schema fields.
- Active-Space highlighting via private CoreGraphics (`CGSMainConnectionID` / `CGSCopyManagedDisplaySpaces`), degrading silently if unavailable.
- Onboarding window with deep links to the three required macOS settings panes.
- Accessibility permission detection, with a banner in the editor until granted.
- `install.sh` / `uninstall.sh` and a LaunchAgent for login auto-start.
