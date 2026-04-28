## Context

`AppDelegate.updateStatusButton()` today sets the status item's title to `" " + truncated(project.name)` when `showNameInMenuBar` is enabled, where `truncated` is a fixed 20-character cap. The status item uses `NSStatusItem.variableLength`, so AppKit grows/shrinks the button width to fit whatever title it's given. Two separate failure modes produce the same user-visible symptom — a missing icon:

1. **System hides the item.** On notched Macs, AppKit will not draw a status item whose frame would overlap the notch. When the title makes the item wide enough to collide with the notch (or to be crowded out by other apps' items that have higher priority), macOS hides ours entirely. The item is still "visible" in the `NSStatusItem.isVisible` sense (we set it true), but the hosting `NSWindow` is off-screen or occluded.
2. **Title is too long to be useful.** Even when not hidden, a 20-character cap is a blunt instrument — on narrow bars it's too long, and on wide bars it needlessly truncates.

We want a single mechanism that produces the longest representation that actually fits, and falls back to icon-only rather than vanishing.

## Goals / Non-Goals

**Goals:**
- The status item is never hidden solely because its title is too long — we always render at least the icon.
- When room exists, the full active-project name is shown; when room is tight, the name is truncated with an ellipsis.
- Re-evaluate on the events that change available width: active project change, name edited, screen configuration change (notch appears/disappears, external display attached), space/full-screen transitions, and explicit occlusion notifications on the status button's window.
- Keep the logic pure and testable — width-and-name in, displayed string out.

**Non-Goals:**
- Forcing the system to show a hidden item. macOS does not expose that control and we won't try to fight it.
- A global hotkey or alternate surface for reaching the app when the item is still hidden at icon-only size. Tracked as a follow-up.
- Changing the `showNameInMenuBar` preference contract. If the user disables the name, we continue to show icon-only regardless of available space.

## Decisions

### D1. Use a layered signal to detect "hidden by system", not a single one

- **Primary signal**: `NSWindow.didChangeOcclusionStateNotification` on `statusItem.button?.window`, checking `occlusionState.contains(.visible)`.
- **Corroborating signal**: the button window's `frame.origin.x`. A clipped item has `origin.x <= 0` or sits inside the notch inset region (`NSScreen.main?.safeAreaInsets.left` / `auxiliaryTopLeftArea`).
- **Re-eval trigger**: `NSApplication.didChangeScreenParametersNotification` plus an observer on `NSStatusItem`'s `length` KVO (if practical) or simply after each title change.

**Why layered:** occlusion notifications have been unreliable on first layout and across space switches; the frame check is a cheap sanity check. Alternatives considered: polling on a timer (rejected — wasteful, still misses transitions); solely relying on `occlusionState` (rejected — known to miss notch clipping on some macOS versions).

### D2. Pure "fit" function drives the title

Factor out a pure function roughly shaped like:

```swift
enum MenuBarTitleForm { case full(String), truncated(String), iconOnly }

func chooseTitleForm(
    name: String,
    showName: Bool,
    availableWidth: CGFloat,
    iconWidth: CGFloat,
    measure: (String) -> CGFloat
) -> MenuBarTitleForm
```

The function picks `full` if it fits, else progressively shortens the name (drop characters from the end, append `…`) until it fits, else returns `iconOnly`. `measure` is injected so tests don't need a real font context.

**Why:** isolates the decision from AppKit side effects and makes the truncation steps covered by unit tests. Alternative considered: computing inline in `updateStatusButton` (rejected — hard to test, and we already have unit coverage for similar logic).

### D3. Estimate available width from the screen, not the status item itself

The status item's own width is downstream of the title we pick, so asking "does the current title fit?" after setting it is circular. Instead:

- Take `NSScreen.main.frame.width`.
- Subtract a conservative reservation for other menu bar items (system clock, control center, input source, etc.) — call it `reservedRightSideWidth`, tunable, default ~260 pt.
- Subtract the notch/safe-area inset if the screen reports one.
- The remainder is the budget for our item; we choose the longest form that fits within it.

This is a heuristic, not a measurement — macOS does not publish remaining bar width. We accept occasional too-aggressive truncation in exchange for robustness. **Alternative considered:** attempting to measure other apps' status items via accessibility APIs. Rejected — brittle, permission-gated, and against the spirit of the platform.

### D4. Debounce re-evaluations

Occlusion and screen-parameter notifications can fire in bursts (e.g., during Mission Control transitions). Coalesce calls to `updateStatusButton()` via a lightweight `DispatchWorkItem` debounce (~100 ms) so we don't thrash the title during animations. Title flicker is worse than being one frame late.

### D5. Preserve the existing `showNameInMenuBar` preference

If `showNameInMenuBar == false`, we short-circuit to `iconOnly` without running the fit logic — same as today. This keeps the preference as a user override and the fit logic as an internal refinement.

## Risks / Trade-offs

- **[Heuristic width budget is wrong]** On setups with lots of third-party menu bar items, our estimate under/overshoots. → Make `reservedRightSideWidth` a compile-time constant for now, but keep the value isolated so it's easy to tune or later promote to a hidden preference.
- **[Occlusion notifications miss edge cases]** E.g., item hidden by a temporary full-screen HUD. → The frame-origin corroborating check catches the common case; a periodic re-eval on space change provides a safety net.
- **[Debounce could swallow a genuine rapid change]** E.g., user switches project twice in 100 ms. → Project-switch driven updates bypass the debounce (they come through a different path in `AppDelegate`). Only screen/occlusion-driven updates are debounced.
- **[No fallback when even icon-only is hidden]** If the bar is so crowded even the naked icon gets clipped, we've done all we can. → Document as a known limitation; follow-up change may introduce a global hotkey.
