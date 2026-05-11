## Why

Today each project stores `space` as a positional 1–16 integer that doubles as both the user-facing Space number and the keyboard-shortcut target ("Switch to Desktop N"). That position is only stable as long as macOS Spaces aren't rearranged. Any time the user reorders Spaces in Mission Control — or removes one, or adds one — projecthub's stored numbers silently desynchronize from the actual shortcut bindings, and clicking a project row will switch to the wrong Space (or beep) until the user notices and re-edits each entry by hand.

This is a latent bug today. It also blocks the upcoming close-project flow, which needs to renumber other projects automatically when the user removes a Space.

The CGS API that `SpaceDetector` already uses exposes a stable per-Space identifier (`id64` / `ManagedSpaceID`). Caching that identifier per project lets us recover the correct positional `space` whenever the Spaces arrangement changes.

## What Changes

- Cache a stable Space identifier (`spaceID64`) per project in `projects.json`, populated when the user assigns or edits a project's Space.
- Watch CGS for changes to the Spaces shape (additions, removals, reorderings) and re-derive each project's positional `space` from its cached `spaceID64`.
- When a project's cached `spaceID64` no longer exists (its Space was removed), mark the project unassigned: the menu row renders disabled with a "Reassign Space…" affordance.
- The user-facing model (Space 1–16) is unchanged. `spaceID64` is a hidden shadow field; the editor still asks for a positional number and resolves it to an `id64` at write time.

## Capabilities

### Modified Capabilities
- `projecthub`: Projects gain an optional cached Space identifier, the active-Space watcher gains shape-change handling, and the project model picks up an "unassigned" rendering state.

## Impact

- **Code:** `Sources/ProjectHubKit/Project.swift` (new optional field, encoder/decoder), a new `SpaceShapeWatcher` (or extension of `SpaceDetector`) that publishes the current `[position: id64]` map, `Sources/AppDelegate.swift` (consume shape changes, recompute project positions, re-render menu), `Sources/EditProjectsWindow.swift` (capture `id64` on Space-picker changes, render unassigned state).
- **APIs:** Extends use of `CGSCopyManagedDisplaySpaces` (already linked) and `NSWorkspace.activeSpaceDidChangeNotification` (already observed). Reading-only; no new private symbols.
- **Storage:** `projects.json` gains an optional `space_id64` per project. Files written by older versions load fine — `spaceID64` is populated lazily on first interaction. The forward-compat extras bucket already round-trips it for older binaries.
- **User-visible:** No new UI in the common case. New disabled-row state when a project's Space disappears (e.g., user closes a Space in Mission Control while projecthub is running).
- **Out of scope:** Re-creating a missing Space; multi-display Space addressing; surfacing `id64` directly in the editor.
