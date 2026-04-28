## Why

The Space picker in the Edit Projects window is hardcoded to 1–9, but macOS Mission Control supports up to 16 Desktop Spaces and the user already has 10 configured. They can't assign a project to their existing Space 10. Two related failures compound this:

1. Even for Spaces within 1–9, clicking a row can silently beep and not switch — this happens when the user has not bound "Switch to Desktop N" in System Settings → Keyboard Shortcuts → Mission Control. Recent macOS releases leave most of these unbound by default. The app today posts `Control+<N>` unconditionally, so an unbound shortcut produces only a system error beep with no explanation. The user hit this on Space 9.
2. The editor lists projects in insertion order, which becomes hard to scan once the list has many entries — the natural reading order is by Space number.

## What Changes

- Raise the maximum Space number from 9 to 16 everywhere it is enforced:
  - The Space picker in the Edit Projects window offers values 1–16.
  - `nextAvailableSpace()` searches 1–16 (falling back to Space 1 only if all 16 are used).
  - `SpaceSwitcher` gains keycode mappings for Spaces 10–16 so a click can send the correct `Control+<key>` shortcut (10 → `0`, 11 → `-`, 12 → `=`; 13–16 reserved for future keys users choose to bind).
- Before synthesizing the `Control+<N>` keypress, the app SHALL check whether the corresponding "Switch to Desktop N" symbolic hotkey is enabled for the target Space. If it is not, the app SHALL surface a dialog explaining which shortcut is missing and deep-linking to the Keyboard Shortcuts pane, instead of silently posting the keys.
- On opening the Edit Projects window, the project list SHALL render sorted ascending by Space number (ties broken by existing order). Subsequent edits within the session do not re-sort until the window is reopened.
- Update the onboarding copy to note that every Space the user wants to switch to needs a "Switch to Desktop N" shortcut bound — including 10+, which macOS never binds by default.

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `projecthub`: change the allowed Space-number range in "Project list persistence" and "Editing the project list" from 1–9 to 1–16; refine "Switch to project's Space on click" to handle the unbound-shortcut case with a clear dialog rather than a silent beep; add a requirement that the Edit Projects window opens sorted by Space number.

## Impact

- Code: `Sources/EditProjectsWindow.swift` (picker range, sort-on-open), `Sources/ProjectHubKit/ProjectStore.swift` (`nextAvailableSpace` range), `Sources/SpaceSwitcher.swift` (keycode table for 10–16, pre-check that the hotkey is bound), new small helper for reading `com.apple.symbolichotkeys` defaults, `Sources/AppDelegate.swift` (surface the unbound-shortcut dialog), `Sources/OnboardingWindow.swift` (copy update).
- Data: no schema change. Existing `projects.json` files remain valid; the `space` field was already typed as `Int`.
- UX: users who rely on insertion order in the editor will see rows reshuffle on open. Users clicking a row whose Space lacks a bound shortcut now get an actionable dialog instead of a beep.
