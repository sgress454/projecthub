## Why

When a project ends — PR merged, repo archived, contract finished — the user wants to *close* it the way they close a document: stop working on it, free the workspace it occupied, and either remove it from view entirely or set it aside for possible later reference. Today the only available action is "delete the row," which leaves all the windows behind on the now-orphaned Space and forces the user to manually hunt down each one.

This proposal adds a single "Close project" action that:

1. closes every window currently sitting on the project's Space (skipping windows pinned to all desktops),
2. uses each app's native close path so unsaved-work prompts behave normally, with a shutdown-style sheet that lets the user cancel if a save dialog stalls progress,
3. then either deletes the project or archives it (preserving name, links, GitHub issues/PRs, OpenSpec change, summary) for possible rehydration later, and
4. leaves the empty Space itself for the user to close in Mission Control — projecthub then auto-renumbers other projects via the stable-space-tracking change.

## What Changes

- Add a "Close Project…" action in the Edit Projects window (per-row, behind a confirm dialog).
- Add a `Confirm` dialog: shows window count, sticky-window count, and offers `Cancel` / `Archive` / `Delete & Close Windows`.
- Refuse to close a project whose Space is occupied by a fullscreen app; surface "exit fullscreen first" copy.
- Add a shutdown-style "Closing windows…" sheet that lists each window, marks it `✓` as it closes, and shows a no-progress timer (auto-cancels after 30s of no closes).
- Implement window enumeration via `CGSCopySpacesForWindows` filtered to the target Space's id64, then close each window via the AX API (`AXCloseButton.performAction`) with a Cmd+W fallback.
- Add an `archived` boolean per project. Archived projects are hidden from the menu bar and shown in a collapsed "Archived" section in Edit Projects. Archiving strips `space`, `space_id64`, `path`, and `claude_enabled` while preserving identity and metadata.
- Add a "Restore" action on archived rows that re-opens the project as unassigned (user picks a Space to rehydrate fully).

## Capabilities

### New Capabilities
- `close-project`: The close-project flow, including window enumeration, the confirm dialog, the shutdown-style progress sheet, the AX/Cmd+W close path, the fullscreen refusal, and post-close project deletion or archival.

### Modified Capabilities
- `projecthub`: Storage gains an `archived` field per project; menu bar list filters out archived projects; Edit Projects gains an Archived section with restore.

## Impact

- **Code:** `Sources/ProjectHubKit/Project.swift` (archived field + storage round-trip), new `Sources/ProjectHubKit/WindowEnumerator.swift` (CGS window→Space mapping), new `Sources/ProjectHubKit/WindowCloser.swift` (AX/keystroke close path with progress callback), new `Sources/CloseProjectCoordinator.swift` (orchestrates the sheet + confirms + state transitions), `Sources/EditProjectsWindow.swift` (Close button, Archived section, Restore button).
- **APIs:** Uses `CGSCopySpacesForWindows` and `CGSCopyWindowsWithOptionsAndTags` (private CoreGraphics, read-only). Uses `AXUIElementCopyAttributeValue` / `AXUIElementPerformAction` (public, requires existing Accessibility permission) to drive the close button. Falls back to `CGEvent` Cmd+W (already used for Space switching).
- **Dependencies:** No new third-party dependencies.
- **Storage:** `projects.json` gains `archived: bool` per project, defaulting to false. Round-trips through the extras bucket on older binaries.
- **Depends on:** `stable-space-tracking` — close-project relies on `space_id64` to identify the target Space stably and on the auto-renumber pipeline to keep other projects' positions correct after the user closes the empty Space in Mission Control.
- **User-visible:** New "Close Project…" button in Edit Projects, new Archived section in Edit Projects, new modal sheets (confirm + progress).
- **Out of scope:** Programmatic Space removal (left to the user via Mission Control); closing windows pinned to all desktops; closing windows on full-screen Spaces (refused); per-app special-case close logic beyond AX-then-Cmd+W; multi-display window enumeration (matches projecthub's existing single-display posture).
