## 1. Schema and storage

- [x] 1.1 Add optional `path: String?` and `claudeEnabled: Bool` (default false) to `Project` in `Sources/Project.swift`.
- [x] 1.2 Add a `Settings` struct on `ProjectList` with `claudeHookInstalled: Bool` (default false); keep unknown-field round-trip behavior.
- [x] 1.3 Bump `ProjectList.version` to `2` on save; accept `version: 1` on read without migration routine.
- [x] 1.4 Unit test: a v0.1 file (name + space only) loads, gets re-saved as version 2 with new fields defaulted, and a subsequent v0.1-shaped file with unknown fields round-trips without data loss.

## 2. Project state model

- [x] 2.1 Define `ProjectStatus` enum: `green`, `yellow`, `red`.
- [x] 2.2 Define a `ProjectRuntimeState` struct holding `status: ProjectStatus` and `working: Bool`.
- [x] 2.3 Implement a `ProjectStateStore` (`ObservableObject`) keyed by project id with thread-safe updates on the main queue.
- [x] 2.4 Implement the transition function as a pure `(ProjectRuntimeState, HookEvent, ClassifierResult?) -> ProjectRuntimeState` — all cases from design D1.
- [x] 2.5 Unit tests for every transition (Notification, Stop×3, UserPromptSubmit, PostToolUse, active-Space-becomes-this).

## 3. Event log and watcher

- [x] 3.1 Define the `events.jsonl` location at `~/Library/Application Support/ProjectHub/events.jsonl`; create parent dirs on demand.
- [x] 3.2 Define `HookEvent` model with fields: `ts` (ISO-8601), `event` (enum), `cwd`, optional `transcript`.
- [x] 3.3 Implement `EventLogWatcher` using `DispatchSourceFileSystemObject` to tail the file; handle file rotation / truncation.
- [x] 3.4 On startup, replay the tail of the log (lookback window: 24 h or until each known project has a terminal event) to reconstruct `ProjectStateStore`.
- [x] 3.5 Implement longest-prefix match from event `cwd` to a project's `path` (must respect path-component boundaries — `/foo/bar` must not match `/foo/bart`).
- [x] 3.6 Rotate the log when it exceeds 10 MB; keep up to 3 rotated files.

## 4. Claude Code hook

- [x] 4.1 Write the hook script at a stable install location (e.g., `~/Library/Application Support/ProjectHub/hooks/projecthub-event.sh`). Script reads stdin JSON, extracts `cwd`, `transcript_path`, `hook_event_name`, and appends one JSON line to `events.jsonl`.
- [x] 4.2 Hook script begins with `exec >/dev/null 2>&1` so it never leaks output or blocks Claude.
- [x] 4.3 Implement `HookInstaller.install()` — read `~/.claude/settings.json`, merge four hook entries (Stop, Notification, UserPromptSubmit, PostToolUse) tagged with a recognizable marker, write atomically via temp + `rename(2)`.
- [x] 4.4 Implement `HookInstaller.uninstall()` — match tagged entries only, remove, write atomically.
- [x] 4.5 Implement `HookInstaller.currentState() -> (installed: Bool, matches: Bool)` so the UI can detect hand-edited `settings.json`.
- [x] 4.6 Unit tests: install into empty settings; install preserving user hooks; uninstall preserving user hooks; round-trip (install → uninstall produces original file).

## 5. Classifier

- [x] 5.1 Define `Classifier.classify(transcriptPath:) async -> ClassifierResult` returning `.question` / `.report` / `.done` / `.failure`.
- [x] 5.2 Read the final assistant message from the transcript jsonl (last line with `role: assistant`).
- [x] 5.3 Invoke `claude -p` as a subprocess with the classification prompt (see design D2); read stdout; 3-second timeout via `DispatchSource`.
- [x] 5.4 Parse output: trim, uppercase, match exactly one of the three tokens; anything else → `.failure`.
- [x] 5.5 Map `.failure` to red in the state transition layer and emit a warning log entry.
- [x] 5.6 Detect absence of `claude` on `PATH` once per app launch; cache the result; short-circuit classification to `.failure`.

## 6. Integration

- [x] 6.1 Wire `EventLogWatcher` → `ProjectStateStore` — each parsed event runs the transition function.
- [x] 6.2 For `Stop` events, launch classification async, and apply the resulting state once the classifier returns.
- [x] 6.3 Extend the existing `activeSpaceDidChangeNotification` observer in `AppDelegate.swift` to apply the red→yellow transition on the newly-active project.
- [x] 6.4 When a project's `claude_enabled` flips from false → true, reset its state to green (drop any stale transitions from when disabled).
- [x] 6.5 When a project's `claude_enabled` flips from true → false, force state to green and `working` false.

## 7. Menu UI

- [x] 7.1 Add a leading status indicator view to each project row in the menu.
- [x] 7.2 Colored indicator: SF Symbol `circle.fill` tinted green / yellow / red per state.
- [x] 7.3 Working indicator: small `NSProgressIndicator` (spinning style, mini size) replacing the circle while `working` is true.
- [x] 7.4 Menu bar icon badge: compose a `NSImage` overlay showing count; tint red if any red, else yellow; hide when zero.
- [x] 7.5 Rebuild the menu / badge on every state change via the `ProjectStateStore` publisher.

## 8. Edit Projects window additions

- [x] 8.1 Add a directory-picker control per row bound to `path`.
- [x] 8.2 Add a per-row "Claude" toggle bound to `claudeEnabled`; disable when `path` is empty (with tooltip explaining why).
- [x] 8.3 Add a global "Enable Claude status" toggle at the top of the window, wired to `HookInstaller`.
- [x] 8.4 Show a preview-of-changes dialog when the global toggle is turned on; confirm writes the file.
- [x] 8.5 Show a warning banner when `claude` CLI is not on `PATH`, explaining classification will default to red.
- [x] 8.6 Show a warning banner when `HookInstaller.currentState()` returns `installed: true, matches: false` (the user has edited our hook entries by hand).

## 9. Documentation

- [x] 9.1 Update `README.md` with v0.2 features: per-project state, hook install, and how to enable monitoring per project.
- [x] 9.2 Document the state machine (colors + transitions) in the Setup Guide section.
- [x] 9.3 Document the privacy implication of classification (Claude sees the final assistant message).
- [x] 9.4 Add a `CHANGELOG.md` v0.2 entry.

## 10. Manual verification

- [x] 10.1 Install hook, set `path` on a test project, enable `claude_enabled`, trigger a Claude permission prompt — row goes red, badge shows 1.
- [x] 10.2 Switch to that Space — row goes yellow, badge shows 1 (yellow).
- [x] 10.3 Respond to Claude and let Claude finish with a clear DONE message — row goes green, badge clears.
- [x] 10.4 Trigger a long-report Stop (ask Claude a research question) — row goes yellow, badge shows 1 (yellow).
- [x] 10.5 While Claude is mid-turn — row shows spinner, menu bar icon pulses, no badge.
- [x] 10.6 Uninstall hook — `~/.claude/settings.json` reverts; pre-existing user hooks still present.

## 10b. In-session additions (spec'd and implemented during smoke tests)

- [x] 10b.1 Subscribe to `PreToolUse` and clear to green+working (matches `PostToolUse`), so red clears the moment a permission is approved.
- [x] 10b.2 `PostToolUse` transition: clear to green+working (instead of preserving prior color) so approval flow removes project from badge while Claude is still executing.
- [x] 10b.3 Per-row × dismiss button on yellow only; `StatusCoordinator.dismiss(projectId:)`; spec + tests.
- [x] 10b.4 Menu bar icon pulses (CABasicAnimation on layer opacity) whenever any project is in `working`.
- [x] 10b.5 `ClaudeCLI.resolve()` probes known paths first, falls back to login shell (no `-i`, no TCC prompts); augmented `PATH` for `claude` subprocess so node-backed CLIs resolve their deps.
- [x] 10b.6 `install.sh` hardened: detect duplicate code-signing certs and fail with a cleanup recipe instead of silently creating a third.

## 11. Archive

- [x] 11.1 Run `openspec validate add-project-status --strict` and resolve any findings.
- [x] 11.2 Archive `add-project-status` so its deltas fold into the canonical `openspec/specs/projecthub/spec.md`. **[Do after 10.x pass and after `add-projecthub-alpha` is archived]**
