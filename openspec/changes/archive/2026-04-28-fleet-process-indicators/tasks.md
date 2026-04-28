## 1. Preferences: iTerm hotkey-window keystroke

- [x] 1.1 Add a `iTermHotkeyWindowShortcut` field (modifier mask + key code, optional) to the `AppPreferences` model and its JSON encoding/decoding, preserving unknown fields.
- [x] 1.2 Add a "Record shortcut" control to the Preferences modal with capture / display / clear behavior.
- [x] 1.3 Wire the preference through to a `HotkeyPoster` helper that posts the configured `CGEvent` keystroke (and returns a status indicating "unset" vs "posted").
- [x] 1.4 Verify the preference round-trips across app restart.

## 2. Process detection

- [x] 2.1 Add a `ProcessSnapshot` value type capturing PID, executable path, argv, and cwd.
- [x] 2.2 Implement `ProcessScanner` using `proc_listpids`, `proc_pidpath`, `sysctl(KERN_PROCARGS2)` for argv (libproc has no argv flavor), and `proc_pidinfo(PROC_PIDVNODEPATHINFO)`; return `[ProcessSnapshot]`.
- [x] 2.3 Implement Fleet-server matcher: executable path ends in `/build/fleet` AND argv contains `serve`.
- [x] 2.4 Implement webpack matcher: argv invokes webpack (yarn-launched or otherwise) with `--progress` or `--watch`.
- [x] 2.5 Implement owner-directory derivation: webpack uses `--output` parent if present else cwd; Fleet uses cwd.
- [x] 2.6 Implement project attribution by longest-prefix path match against `project.path` (reuses existing `matchProject`).
- [x] 2.7 Add unit tests covering: cwd attribution, `--output` cross-project attribution, longest-prefix tie-break, no-match → no indicator, missing-project-path projects ignored.

## 3. Hover-detail derivation

- [x] 3.1 Implement Fleet listen-port discovery via argv (`--server_address`/`--listen`/`--port`, both space- and `=`-separated). Socket-inspection fallback (`PROC_PIDLISTFDS` + `PROC_PIDFDSOCKETINFO`) deferred — argv parsing satisfies the spec's "neutral fallback when port unknown" scenario for v1; the user's workflow always passes the port via argv.
- [x] 3.2 Implement webpack `--output` resolution to absolute path (relative to the launching cwd).
- [x] 3.3 Add unit tests for argv parsing of port and `--output`.

## 4. Scan lifecycle

- [x] 4.1 Add a `ProcessIndicatorService` that owns the scan timer (2s interval), runs `ProcessScanner`, applies matchers + attribution, and exposes a published `[UUID: FleetProcessIndicators]` map.
- [x] 4.2 Wire the service into the AppDelegate so menu rendering reads the latest snapshot.
- [x] 4.3 Confirm indicator removal when a process exits (next scan tick) — a vanished match drops the entry, the published-value `!=` check fires the rebuild.

## 5. Menu bar row redesign

- [x] 5.1 Update the custom NSMenuItem row view to drop the "Space N" suffix from project rows.
- [x] 5.2 Add right-aligned 🌐 and 🎨 indicator slots (rendered conditionally) next to the existing terminal icon.
- [x] 5.3 Make each indicator a separate click target distinct from the row body (extended `hitTest`).
- [x] 5.4 Add tooltips on each indicator (NSButton.toolTip — AppKit handles the tracking-area mechanics for menu-item-hosted custom views).
- [x] 5.5 Verify that clicking the row body still switches to the project's Space and that clicking an indicator does NOT — covered by the hitTest routing; `summonITermHotkey()` does not invoke the row's Space-switch path. Manual verification in §8.

## 6. Hotkey-window summon click handler

- [x] 6.1 Wire indicator clicks to `HotkeyPoster.postITermHotkey()` via `AppDelegate.summonITermHotkey()`.
- [x] 6.2 If the keystroke is unset, surface a dialog with an "Open Preferences" button.
- [x] 6.3 Reuse the existing Accessibility-permission precondition check (the existing `promptForAccessibility()` dialog is shown when `HotkeyPoster` returns `.notTrusted`).

## 7. Spec updates

These deltas live in `openspec/changes/fleet-process-indicators/specs/` and will be merged into `openspec/specs/` automatically by `/opsx:archive`. Boxes are checked when the deltas exist and accurately describe shipped behavior.

- [x] 7.1 `MODIFIED` requirement for `projecthub` spec (drop "Space N" from menu rows) authored in change folder.
- [x] 7.2 `ADDED` requirement for `app-preferences` spec (iTerm hotkey-window keystroke preference) authored in change folder.
- [x] 7.3 New `fleet-process-indicators` spec authored in change folder.

## 8. Manual verification

- [x] 8.1 Configure an iTerm2 hotkey window per the project README / change notes; record its keystroke in projecthub Preferences.
- [x] 8.2 With one Fleet server running, confirm 🌐 appears on the owning project's row and the port shows on hover.
- [x] 8.3 With webpack `--output` writing into a different project's `assets/`, confirm 🎨 attaches to the *server* project (not the cwd project) and the output dir shows on hover.
- [x] 8.4 Click each indicator; confirm the iTerm hotkey window is summoned and the project's Space is NOT switched.
- [x] 8.5 Click the row body; confirm Space-switch still works and no keystroke is posted.
- [x] 8.6 Quit and relaunch; confirm indicators reappear within one scan interval and the keystroke preference persists.
