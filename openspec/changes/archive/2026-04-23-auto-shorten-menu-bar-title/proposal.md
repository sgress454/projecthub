## Why

On Macs with a notch (or when the menu bar is crowded by other apps), macOS silently hides the entire ProjectHub status item when its title would overlap the notch or run out of space. Today the title is capped at a fixed 20 characters regardless of available room, so long project names plus a badge still push the item off-bar — and when that happens the user loses not just the name but the icon, the state indicator, and the click target. The user can't even tell the app is running.

## What Changes

- Detect at runtime when the status item is clipped / hidden by the system (via occlusion state and/or the status button window's frame), rather than relying only on a static character cap.
- Progressively shorten the displayed title: full name → truncated name → icon-only, picking the longest form that still fits.
- Re-evaluate the title when inputs change (active project switches, name edited, screen configuration changes, full-screen apps enter/exit) so the item recovers when space is freed.
- Keep the existing "Show project name in menu bar" preference semantics — this change refines *how* the name is shown when enabled, not whether it is shown.

Out of scope: adding a global hotkey / alternate access path when the item is still hidden even at icon-only size. Noted in design as a follow-up.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `projecthub`: adds a new requirement for how the menu bar status-item title is rendered (full / truncated / icon-only), formalizing behavior that today is only expressed in code. No existing spec-level behavior is overturned, so the delta is purely additive under the `projecthub` capability.

## Impact

- **Code**: `Sources/AppDelegate.swift` (`updateStatusButton`, `truncatedForMenuBar`, `maxMenuBarNameChars`); likely a small new helper type for measuring fit and observing occlusion/screen changes.
- **APIs**: none external. Internal: the preference `showNameInMenuBar` keeps its meaning.
- **Dependencies**: none added. Uses existing AppKit (`NSStatusItem`, `NSWindow.didChangeOcclusionStateNotification`, `NSApplication.didChangeScreenParametersNotification`).
- **Tests**: unit coverage for the truncation/fit logic (pure function over available width and name); manual verification on notched vs. non-notched displays and with crowded menu bars.
- **Risk**: occlusion notifications can be noisy or late on first layout; design needs to debounce and combine signals.
