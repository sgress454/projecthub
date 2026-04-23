## Context

ProjectHub renders the menu bar dropdown as an `NSMenu` built in `AppDelegate`/`ProjectRowView`-adjacent code, with per-project submenus assembled from `Project` metadata. Projects already carry an optional `path: String?` (see `Sources/ProjectHubKit/Project.swift`). The app currently has no general preferences layer — the only persisted user state is `projects.json` and hook-install state.

Two small user-facing actions are being added plus the first real "app preference," so we need a minimal preferences store and modal that can grow without becoming a grab-bag.

## Goals / Non-Goals

**Goals:**
- Zero-friction copy of a project's directory from the submenu.
- One-click launch of the project's directory in the user's terminal, with the launch behavior clearly indicating when a directory is missing.
- A preferences surface that holds terminal choice today and is extensible.

**Non-Goals:**
- Supporting terminals beyond iTerm2 and Terminal.app in v1 (e.g., Ghostty, Warp). The design keeps this open but does not ship more entries.
- Changing `projects.json` schema (no per-project overrides of terminal choice).
- Reveal-in-Finder, open-in-editor, or other directory actions — scoped out deliberately.

## Decisions

### 1. Preferences storage: a new JSON file, not `UserDefaults`

New file `~/Library/Application Support/ProjectHub/preferences.json` holding a versioned object (`version: 1`, `terminalApp: "iterm2" | "terminal"`).

Rationale: `projects.json` already lives there, the app's storage idiom is JSON + forward-compat unknown-field round-tripping, and writing structured user state to `UserDefaults` would be the outlier. Keeps all app state co-located and diffable.

Alternatives considered: `UserDefaults` (rejected — splits state across two mechanisms); bundling into `projects.json` (rejected — preferences are app-level, not list-level).

### 2. Terminal launch: `NSWorkspace.open(_:withApplicationAt:configuration:)` against a resolved `.app` bundle URL

Resolve the chosen terminal's bundle URL via `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` (iTerm2 = `com.googlecode.iterm2`, Terminal = `com.apple.Terminal`), then `open(directoryURL, withApplicationAt: appURL, …)`.

Rationale: both iTerm2 and Terminal.app natively interpret an opened directory as "start a shell there." No AppleScript required, no assumptions about shell configuration, no subprocess.

Alternatives considered: shelling out to `/usr/bin/open -a <app> <path>` (rejected — needless subprocess and harder error handling); AppleScript per terminal (rejected — brittle and asks for Automation permission).

### 3. Default terminal detection on first launch

On app launch, if `preferences.json` is absent, detect iTerm2 via `urlForApplication(withBundleIdentifier: "com.googlecode.iterm2")` and persist `terminalApp = "iterm2"` if present, else `"terminal"`. Subsequent launches read the persisted value verbatim — we do not re-detect, so uninstalling iTerm2 just surfaces a launch failure the user can fix in Preferences.

### 4. Directory submenu section: header row + value row

Submenu order becomes: Issues → PRs → **Directory** (new, when path set) → Links → Open All → AI Summary.

Layout: a non-clickable section header labeled "Directory" followed by a clickable item showing the directory's basename, ellipsized to a max width (≈32 chars), with the full path as the item's `toolTip`. Clicking writes the full absolute path to `NSPasteboard.general`.

Rationale: matches the existing section idiom (Issues/PRs/Links also use header + items). Basename keeps the row scannable; tooltip exposes the full path for verification before copy. Absolute path in clipboard because that's what users paste into terminals and scripts.

### 5. Main-row trailing "open in terminal" control

A far-right-aligned `NSButton` (borderless, templated SF Symbol, likely `terminal`) embedded in the project row's custom view. Pinned to the row's trailing edge as a standalone subview (outside the main info stack) so it stays flush-right regardless of how much horizontal space the name and metadata need. Enabled iff `project.path != nil` and the resolved terminal app URL is non-nil; otherwise shown greyed (disabled state via `isEnabled = false` with reduced alpha), which doubles as the "no directory" visual cue.

Click handler opens the directory in the chosen terminal and closes the menu (matches existing "click a PR opens browser, menu closes" behavior). Clicking the button does NOT switch Spaces — action is swallowed before the row's click handler.

Rationale: lives in the existing `ProjectRowView` custom view rather than a new NSMenu item level, since we already have a custom row. Disabled-greyed is the explicit UX cue the user asked for.

### 6. Preferences modal surfacing

"Preferences…" opens from both the status-item right-click context menu and a button in the Edit Projects window toolbar. The modal is a small sheet/window with a single "Terminal" popup button (iTerm2, Terminal.app) — writes are immediate (no explicit Save).

Rationale: the existing Edit Projects window already acts as the settings surface; the status-item right-click is the idiomatic macOS entry point and we want it reachable without opening Edit Projects.

## Risks / Trade-offs

- **Terminal not installed at launch time** → the launch call fails. Mitigation: if `urlForApplication` returns nil for the configured choice, disable the row button (same greyed state as "no path"), tooltip reads "iTerm2 not installed — change in Preferences."
- **User expects more terminals (Ghostty, Warp, Alacritty)** → v1 picker only has two. Mitigation: the persisted value is a string id, so adding entries later is additive; the design does not bake the enum into the storage format in a way that would break.
- **Clipboard copy has no confirmation** → users may not realize the copy happened. Mitigation: brief `NSUserNotification`-style feedback is out of scope; the submenu closing on click is the same feedback pattern used by all other submenu items, which is acceptable.
- **Menu rebuild cost** → adding a Directory section to every submenu slightly increases rebuild work on menu open. Mitigation: the section is skipped entirely when `path == nil`, matching how empty Issues/PRs/Links sections are skipped.

## Migration Plan

No migration needed. Preferences file is created on first write. Existing installs get default behavior (iTerm2 if installed, else Terminal.app) on first app launch after update.
