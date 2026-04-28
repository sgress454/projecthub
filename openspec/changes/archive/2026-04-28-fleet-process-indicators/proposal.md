## Why

Across multiple concurrent projecthub projects, only one Fleet server (`./build/fleet serve`) and frontend webpack build (`yarn ... webpack`) typically run at a time, but they can live in any project's directory and on any Space. Finding the live ones — to tail logs, kill them, or restart in another project — currently requires hunting through Spaces and iTerm windows. The menu bar already knows each project's directory, so it can attribute running processes back to projects and surface them at a glance. Pairing the indicators with a click-to-summon for an iTerm hotkey window (a single, always-reachable home for Fleet processes) removes the hunt entirely.

## What Changes

- Detect running Fleet server and webpack-build processes via a periodic process scan and attribute each to a project by matching its working directory (or webpack's `--output` parent) against `project.path`.
- Show a 🌐 indicator on a project row when a Fleet server is attributed to it, and a 🎨 indicator when a webpack build is attributed to it. Both render right-aligned alongside the existing terminal icon, only when the corresponding process is detected.
- On hover, 🌐 shows the server's listen port and 🎨 shows the webpack `--output` directory if present (otherwise the project's own directory).
- On click, either indicator posts a user-configured iTerm hotkey-window keystroke (e.g. `⌃⌥⌘T`), summoning the user's dedicated Fleet console window from any Space.
- Add a new `app-preferences` field for the iTerm hotkey-window keystroke, edited via the Preferences modal in the same idiom as existing shortcut/terminal preferences.
- **BREAKING (UI only):** Remove the "Space N" suffix from menu bar project rows. The Space number remains visible and editable in the Edit Projects window.

## Capabilities

### New Capabilities
- `fleet-process-indicators`: Detection of running Fleet server / webpack processes, their attribution to projects via path matching, the corresponding menu bar indicators with hover detail, and the click-to-summon behavior for the iTerm hotkey window.

### Modified Capabilities
- `projecthub`: Menu bar rows no longer display the assigned Space number; Space number is shown only in the Edit Projects window.
- `app-preferences`: Adds a new persisted preference for the iTerm hotkey-window keystroke, with a corresponding control in the Preferences modal.

## Impact

- **Code:** `Sources/AppDelegate.swift` (menu rendering, row layout, click handlers), a new process-scanning component, additions in `Sources/EditProjectsWindow.swift` or the Preferences modal for the new keystroke field, the project model / preferences store for the new field.
- **APIs:** Uses macOS `libproc` (`proc_listpids`, `proc_pidpath`, `proc_pidinfo` with `PROC_PIDVNODEPATHINFO`) for process introspection — no shell-out required. Posts a `CGEvent` keystroke for the hotkey-window summon, mirroring the existing Space-switch posting path.
- **Dependencies:** No new third-party dependencies.
- **User-visible:** Menu rows change appearance (Space number gone, conditional indicators appear). Users who want the indicators to do anything useful must configure both an iTerm hotkey window and the corresponding keystroke preference in projecthub; without configuration, the indicators still appear but clicking them is a no-op (or surfaces a dialog, mirroring the Space-shortcut-missing pattern).
- **Out of scope:** Launching processes from projecthub; managing multiple concurrent Fleet servers as separate first-class entities; generic per-project task definitions beyond the hardcoded Fleet patterns.
