## Why

Opening a project in a terminal and copying its path are the two most common follow-ups after switching Spaces, and both currently require the user to leave the menu bar. Surfacing them directly in the menu makes the app a real launchpad and — as a side benefit — makes it obvious at a glance which projects are still missing a directory assignment.

## What Changes

- Add a "Directory" section at the top of each project's submenu when a directory is assigned: a section header with the ellipsized directory name, clicking copies the full path to the clipboard.
- Add a trailing "open in terminal" icon on each main menu project row. Enabled when a directory is assigned (opens the directory in the user's configured terminal); greyed out otherwise.
- Add a Preferences modal with a terminal-application picker (iTerm2 / Terminal.app), persisted across launches. Default: iTerm2 if installed, else Terminal.app.

## Capabilities

### New Capabilities
- `app-preferences`: User-level app preferences (initially: terminal application choice), persisted to disk, editable via a Preferences modal.

### Modified Capabilities
- `project-submenu`: Add "Directory" section at the top of the submenu that shows the ellipsized directory name and copies the full path on click.
- `projecthub`: Add a trailing per-row "open in terminal" control on the main menu bar dropdown; disabled when a project has no `path`.

## Impact

- New `PreferencesStore` (persisted under Application Support) and `Preferences` modal.
- Terminal launcher helper that invokes iTerm2 or Terminal.app via `NSWorkspace`/AppleScript or `open -a`.
- Changes to the main menu row view (trailing icon button) and submenu builder (Directory section).
- New menu item ("Preferences…") surfaced from the app menu and/or Edit Projects window.
- No storage-schema change to `projects.json`.
