## Context

ProjectHub maps each project to a macOS Desktop Space and switches to that Space by synthesizing a `Control+<N>` keypress corresponding to macOS's "Switch to Desktop N" Mission Control shortcut. The current implementation hardcodes the range 1–9 in three places — the picker UI, `ProjectStore.nextAvailableSpace()`, and `SpaceSwitcher.keyCodes` — and does no checking of whether the target shortcut is actually bound in System Settings.

Two real user-visible problems have surfaced:

1. A user with 10 Spaces cannot assign a project to Space 10: the picker only offers 1–9.
2. Even within 1–9, clicking a row can silently beep (the macOS "unbound key" feedback) instead of switching, because recent macOS releases do not bind all "Switch to Desktop N" shortcuts by default.

Separately, the Edit Projects window currently renders projects in insertion order. As a user accumulates 10+ entries, the list becomes hard to scan when looking up "which project is on Space 7?" Sorting by Space number on open matches the mental model users already have when picking rows from the menu bar.

## Goals / Non-Goals

**Goals:**
- Allow any Space number from 1 to 16, matching the range macOS exposes via the "Switch to Desktop 1…16" symbolic hotkeys.
- Fail loudly and usefully when the shortcut for the target Space is not bound, instead of silently beeping.
- Open the Edit Projects window sorted ascending by Space number.

**Non-Goals:**
- Programmatically binding macOS keyboard shortcuts on the user's behalf. That would mutate `com.apple.symbolichotkeys.plist`, which is fragile and user-hostile.
- Switching Spaces without using `Control+<N>` (e.g., private CoreGraphics APIs, AppleScript Mission Control automation). The keyboard-shortcut approach is intentionally the supported path and we're staying with it.
- Live re-sorting the Edit Projects window as the user edits rows. Sort order is applied on open only, so rows don't jump around while the user is typing.
- Raising the cap above 16. macOS's Mission Control shortcuts stop at `Switch to Desktop 16`, so 16 is the meaningful ceiling.

## Decisions

### 1. Cap at 16, not 9 and not unbounded

macOS's `com.apple.symbolichotkeys` exposes `Switch to Desktop 1` (id 118) through `Switch to Desktop 16` (id 127 for 10, 229–234 for 11–16, depending on macOS version — the exact IDs are read dynamically, not assumed). 16 is the system ceiling, so that's the cap. We do not try to support arbitrary N.

**Alternative considered:** cap at 10 since that's what the user hit today. Rejected — the cost of supporting 11–16 is tiny (a keycode table extension) and avoids a second round of this same bug.

### 2. Keycode mapping for Spaces 10–16

`SpaceSwitcher.keyCodes` gains entries for 10–16. macOS does not define default `Switch to Desktop N` shortcuts above 9, so the mapping we pick is purely a convention the user configures to match:

| Space | Key      | Keycode |
|------:|:---------|:--------|
| 10    | `0`      | 0x1D    |
| 11    | `-`      | 0x1B    |
| 12    | `=`      | 0x18    |
| 13–16 | (unset)  | —       |

Mapping Space 10 → `Control+0` is the most common convention users pick. 11 and 12 use the two keys immediately to the right of `0`, which are natural extensions of the number row. We deliberately do not assign 13–16: there is no natural keyboard convention past `=`, and any choice we made would conflict with common system or app shortcuts.

Users with 13+ Spaces will see those options in the picker but clicking a row mapped to one of them falls through to the "shortcut not bound" dialog (see Decision 3) with instructions to assign a shortcut in System Settings. This is honest: we tell them what to bind rather than pretending we know.

**Alternative considered:** omit 13–16 from the picker entirely. Rejected — the user's existing complaint is "the picker caps me artificially"; capping at 12 just moves the cliff. Better to offer 1–16 and surface a clear "bind the shortcut" message when needed.

### 3. Detecting unbound shortcuts before posting the keypress

Before posting `Control+<N>`, the app reads `com.apple.symbolichotkeys` preferences (via `CFPreferencesCopyAppValue` with the `AppleSymbolicHotKeys` key on the `com.apple.symbolichotkeys` domain) and checks whether the hotkey entry for the relevant "Switch to Desktop N" ID is present AND has `enabled: true`. If not, the app shows a modal alert:

> Switch to Desktop N is not enabled in macOS Keyboard Shortcuts. ProjectHub needs this shortcut to switch to this project's Space.
> [Open Keyboard Shortcuts] [Cancel]

The "Open Keyboard Shortcuts" button deep-links to `x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts` (Mission Control pane).

**Why read defaults instead of just posting and detecting failure:** there is no reliable failure signal from `CGEvent.post` — an unbound shortcut beeps but no error is raised to the caller. The only deterministic check is reading the symbolic-hotkey state ahead of time.

**Alternative considered:** observe active-Space changes post-click and show the dialog if the Space didn't change within ~200 ms. Rejected — racy, adds a delay even on success, and gives a worse message ("something failed") than a pre-check ("this specific shortcut isn't bound").

**Alternative considered:** bind the shortcut on the user's behalf. Rejected (see Non-Goals) — mutating another app's plist is fragile and the user has no expectation that ProjectHub manages their system shortcuts.

The hotkey-ID mapping (Switch-to-Desktop N → symbolic hotkey integer ID) is encoded as a static table in a new `MissionControlShortcuts` helper. If the defaults domain can't be read at all (rare), the check is treated as "unknown, assume enabled" and the keypress is posted as today — i.e., we degrade to the current behavior rather than blocking Space switching for a preference-read edge case.

### 4. Sort on open, not live

The Edit Projects window's `ForEach(store.projects)` is replaced with iteration over a view-local sorted snapshot computed in `.onAppear` (or equivalent SwiftUI state initialization). The snapshot re-sorts only when the window is opened; edits within the session don't reshuffle rows.

Sort key: ascending by `space`, with stable fallback on the project's existing array position (to keep order deterministic for ties).

**Alternative considered:** sort the underlying `store.projects` array itself on open. Rejected — the menu bar dropdown iterates the same array, and changing its order would also change the visual order users have in their muscle memory for the menu bar. Keeping sort local to the editor's view preserves menu-bar order.

**Alternative considered:** live sort on every edit. Rejected — it would make the user's row jump while they're typing a name or changing a Space number, which is jarring.

## Risks / Trade-offs

- **Symbolic-hotkey schema changes across macOS versions** → the ID table we encode for "Switch to Desktop N" may drift on future macOS releases. Mitigation: if the expected ID isn't found in the defaults, fall back to "assume enabled" and post the keypress as today. The worst-case regression is the current behavior (silent beep), not something worse.
- **User-modified keycap layouts (Dvorak, international)** → our keycodes target physical positions on a US QWERTY number row. On other layouts, `Control+0` etc. may not produce the right character even though macOS binds the shortcut by position. Mitigation: none at this time — this is the existing behavior for 1–9 too, and no users have reported issues.
- **Insertion-order users** → someone who has internalized the current insertion-order layout of the editor will see it reshuffle on the next open. Mitigation: the new order (ascending by Space) is the order the user already sees in the menu bar, so this should be a net improvement in cognitive load.
- **Reading other apps' preferences domain** → `CFPreferencesCopyAppValue` on `com.apple.symbolichotkeys` is a read-only operation and a long-standing stable path (Hammerspoon, Karabiner, and other utilities read it routinely). Mitigation: treat unreadable/missing data as "assume enabled" so we never block on a preference-read failure.
