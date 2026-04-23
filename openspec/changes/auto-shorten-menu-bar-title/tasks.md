## 1. Pure fit logic

- [x] 1.1 Introduce a `MenuBarTitleForm` enum (`full`/`truncated`/`iconOnly`) in a new file under `Sources/ProjectHubKit/` (alongside other menu-bar helpers).
- [x] 1.2 Implement a pure `chooseTitleForm(name:showName:availableWidth:iconWidth:measure:)` function that returns the longest form that fits the given width budget.
- [x] 1.3 Unit-test the function: full fits, progressive truncation produces ellipsis at the right length, under-budget falls back to `iconOnly`, `showName == false` always returns `iconOnly`, empty/whitespace names behave sanely.

## 2. Width budget estimation

- [x] 2.1 Add a helper that computes the available menu bar width budget: `NSScreen.main.frame.width` minus a `reservedRightSideWidth` constant minus any left safe-area inset (notch).
- [x] 2.2 Unit-test the helper with representative inputs (notched MacBook, external display, no notch).

## 3. Wire AppDelegate to the fit logic

- [x] 3.1 Replace the fixed-cap `truncatedForMenuBar` / `maxMenuBarNameChars` logic in `AppDelegate.updateStatusButton()` with a call into the new fit function. Use the button's current font for `measure`.
- [x] 3.2 Ensure that when the result is `iconOnly`, the button title is set to an empty string so AppKit collapses the item width to the icon.
- [x] 3.3 Remove the now-unused `maxMenuBarNameChars` constant and helper if nothing else depends on them.

## 4. Re-evaluation triggers

- [x] 4.1 Observe `NSApplication.didChangeScreenParametersNotification` and trigger a (debounced) status-button update.
- [x] 4.2 Observe `NSWindow.didChangeOcclusionStateNotification` on the status item's button window and trigger a (debounced) status-button update.
- [x] 4.3 Add a ~100 ms debounce so burst notifications (e.g., during Mission Control) don't flicker the title.
- [x] 4.4 Confirm the existing active-project change and name-edit paths still call `updateStatusButton()` (or add calls if missing) so those updates re-evaluate immediately and bypass the debounce. — active-space observer, `ProjectStore.$projects` sink, sync completion, and the show-name toggle all call `updateStatusButton()` directly.

## 5. Manual verification

- [ ] 5.1 On a notched display, configure a project whose name would previously hide the status item; verify the title shortens to fit or falls back to icon-only.
- [ ] 5.2 Attach/detach an external display; verify the title re-evaluates when the main screen changes.
- [ ] 5.3 Crowd the menu bar with other apps; verify the icon remains visible and the title shortens accordingly.
- [ ] 5.4 Toggle the "Show project name in menu bar" preference off/on; verify the icon-only short-circuit works.
- [ ] 5.5 Switch Spaces between projects with short and long names; verify the title swaps and re-fits without flicker.

## 6. Cleanup

- [x] 6.1 Update `CHANGELOG.md` with a user-facing note.
- [x] 6.2 Run full test suite (`swift test`) and confirm it passes. — 116/116 tests passing.
