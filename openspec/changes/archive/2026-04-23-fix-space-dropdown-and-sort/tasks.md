## 1. Raise the Space cap to 16

- [x] 1.1 Update the Space picker in `Sources/EditProjectsWindow.swift` (around line 275) to iterate `1...16` instead of `1...9`.
- [x] 1.2 Update `nextAvailableSpace()` in `Sources/ProjectHubKit/ProjectStore.swift` (around line 156) to search `1...16` with fallback to Space 1 only when all 16 are occupied.
- [x] 1.3 Extend `Sources/SpaceSwitcher.swift` `keyCodes` table with entries for 10 (`0`, 0x1D), 11 (`-`, 0x1B), and 12 (`=`, 0x18). Leave 13–16 unmapped; the unbound-shortcut dialog covers them.
- [x] 1.4 Add a `ProjectHubKit` unit test asserting `nextAvailableSpace()` returns 10 when Spaces 1–9 are in use and falls back to 1 only when 1–16 are all used.

## 2. Pre-check "Switch to Desktop N" before posting keypress

- [x] 2.1 Add a new `MissionControlShortcuts` helper (in `Sources/ProjectHubKit/` or `Sources/`) exposing `isSwitchToDesktopEnabled(space: Int) -> Bool?`. Return `nil` when the preferences domain cannot be read.
- [x] 2.2 Implement the helper by reading `AppleSymbolicHotKeys` from the `com.apple.symbolichotkeys` defaults domain via `CFPreferencesCopyAppValue`, indexing by the documented symbolic-hotkey IDs for Switch-to-Desktop 1–16, and checking the `enabled` flag.
- [x] 2.3 Unit test the helper by injecting a fake defaults-reader seam (so tests don't touch the user's real preferences): cover the enabled, disabled, missing-entry, and unreadable-domain cases.
- [x] 2.4 In `SpaceSwitcher.switchTo(space:)` call the helper before posting the keypress. If the helper returns `false`, do NOT post the keypress and instead surface an "unbound shortcut" signal to `AppDelegate`.
- [x] 2.5 If the helper returns `nil` (unknown), proceed with posting the keypress — this preserves today's behavior on unreadable preferences.
- [x] 2.6 In `Sources/AppDelegate.swift`, present an `NSAlert` when the unbound-shortcut signal fires. Text: "'Switch to Desktop \(n)' is not enabled in macOS Keyboard Shortcuts. ProjectHub needs this shortcut to switch to this project's Space." Buttons: `Open Keyboard Shortcuts` (opens `x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts`) and `Cancel`.
- [x] 2.7 Update `Sources/OnboardingWindow.swift` copy: clarify that every Space the user wants to switch to needs a "Switch to Desktop N" shortcut bound, explicitly including spaces 10–16 which macOS does not bind by default.

## 3. Sort Edit Projects list by Space on open

- [x] 3.1 In `Sources/EditProjectsWindow.swift`, replace the direct `ForEach(store.projects)` (around line 34) with iteration over a view-local `@State` array of project IDs captured once when the window appears, ordered ascending by `space` (stable fallback on stored index).
- [x] 3.2 Confirm by inspection that the menu bar dropdown in `AppDelegate.swift` still iterates `store.projects` in its stored order — the sort must be local to the editor view, not a mutation of the store. (Menu bar does its own `projects.sorted(by: { $0.space < $1.space })` without mutating the store; the new editor sort is likewise view-local.)
- [x] 3.3 Verify manually: open the editor with projects in stored order A/3, B/1, C/2 → rows show B, C, A; change B's Space to 8 → B's row stays put until the window is closed and reopened; close and reopen → rows show C (2), A (3), B (8); on-disk `projects.json` still has the original A, B, C order. — Initial implementation only re-seeded on SwiftUI `onAppear`, which the cached `editWindow` suppressed on reopen; added `editProjectsWindowWillShow` notification from `AppDelegate.openEditWindow()` + `.onReceive` in the view so re-seed now fires on every open.

## 4. Update the base `projecthub` spec

- [x] 4.1 When the change is archived, ensure `openspec/specs/projecthub/spec.md` reflects the 1–16 range in "Project list persistence" and "Editing the project list", the new unbound-shortcut scenarios under "Switch to project's Space on click", and the new "Edit Projects window default sort" requirement.

## 5. Validate

- [x] 5.1 Run `swift test` — existing tests plus the new ones in tasks 1.4 and 2.3 must pass. (101/101 passing; includes 7 new `MissionControlShortcutsTests` and 3 new `StorageTests` cases.)
- [x] 5.2 Manually verify in a running build: (a) picker offers 1–16; (b) assigning a project to Space 10 and clicking it with `Control+0` bound switches correctly; (c) clicking a row whose Space shortcut is disabled shows the new dialog and does not beep; (d) editor opens sorted by Space; (e) menu bar dropdown order is unchanged. — Confirmed by user in follow-up session (sort on reopen fix verified).
- [x] 5.3 Update `CHANGELOG.md` with a user-facing note summarizing the three changes.
