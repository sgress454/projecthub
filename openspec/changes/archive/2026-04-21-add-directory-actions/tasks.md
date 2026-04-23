## 1. Preferences store

- [x] 1.1 Add `Preferences` model (struct with `version: Int`, `terminalApp: TerminalChoice`, round-tripped unknown fields via dictionary)
- [x] 1.2 Add `TerminalChoice` enum with `iterm2` (`com.googlecode.iterm2`) and `terminal` (`com.apple.Terminal`) cases plus associated bundle identifiers
- [x] 1.3 Add `PreferencesStore` that loads/saves `~/Library/Application Support/ProjectHub/preferences.json`
- [x] 1.4 On first load (file absent), detect iTerm2 via `NSWorkspace.urlForApplication(withBundleIdentifier:)`, set default, persist
- [x] 1.5 Unit tests: file absent → default + persist; file present → verbatim read; unknown fields → round-trip

## 2. Terminal launcher

- [x] 2.1 Add `TerminalLauncher` helper with `open(directoryURL:using:)` that resolves bundle id → app URL and calls `NSWorkspace.open(_:withApplicationAt:configuration:)`
- [x] 2.2 Add `isAvailable(_:)` for a `TerminalChoice` returning whether its bundle id resolves on this system
- [x] 2.3 Graceful handling when app URL is nil: log warning, return failure (no crash)
- [x] 2.4 Unit tests for bundle id resolution paths (using injected `NSWorkspace`-like protocol)

## 3. Preferences modal

- [x] 3.1 Create `PreferencesWindowController` with a small sheet/window containing a "Terminal" `NSPopUpButton` (iTerm2, Terminal.app)
- [x] 3.2 Bind popup selection → `PreferencesStore.save()` on change (no explicit Save button)
- [x] 3.3 Add "Preferences…" button/toolbar item to `EditProjectsWindow`
- [x] 3.4 Add "Preferences…" item to the status-item right-click context menu
- [x] 3.5 Manual test: open modal from both entry points, change terminal, verify `preferences.json` updates immediately

## 4. Submenu "Directory" section

- [x] 4.1 In the submenu builder, insert a "Directory" section header at the top when `project.path != nil`
- [x] 4.2 Add a clickable item showing `URL(fileURLWithPath: path).lastPathComponent`, truncated to ~32 chars with ellipsis
- [x] 4.3 Set the item's `toolTip` to the full absolute path
- [x] 4.4 Click handler writes full absolute path to `NSPasteboard.general` (`clearContents()` + `setString(_:forType: .string)`)
- [x] 4.5 Ensure the section precedes Issues, PRs, Links, Open All, and AI Summary in that order
- [x] 4.6 Manual test: assign a path, open submenu, click "Directory" item, paste into another app to confirm

## 5. Main row terminal control

- [x] 5.1 Add a trailing `NSButton` (borderless, `NSImage(systemSymbolName: "terminal", …)` template) to `ProjectRowView`
- [x] 5.2 Determine enabled state: `project.path != nil && TerminalLauncher.isAvailable(preferences.terminalApp)`
- [x] 5.3 Apply greyed-disabled styling when disabled (reduced alpha or standard disabled appearance)
- [x] 5.4 Tooltip when disabled because of missing path: "No directory assigned"
- [x] 5.5 Tooltip when disabled because configured terminal is missing: "iTerm2 not installed — change in Preferences" (adapted per choice)
- [x] 5.6 Click handler: call `TerminalLauncher.open(directoryURL: URL(fileURLWithPath: path), using: preferences.terminalApp)`, then close the menu; ensure click does NOT propagate to the row's Space-switch action
- [x] 5.7 Update row layout so the trailing button coexists with the existing dismiss control without overlap
- [x] 5.8 Manual test: rows without path show greyed icon; rows with path launch configured terminal and menu closes; Space is not switched

## 6. Integration & validation

- [x] 6.1 Wire `PreferencesStore` into `AppDelegate` as a shared instance consumed by the submenu builder and row view
- [x] 6.2 Re-render menu when preferences change (so row enabled states update after a terminal-choice switch)
- [x] 6.3 Manual regression pass: all existing submenu sections still render in order (Directory → Issues → PRs → Links → Open All → AI Summary)
- [x] 6.4 Update `CHANGELOG.md` entry for this change
- [x] 6.5 `openspec validate add-directory-actions --strict` passes
