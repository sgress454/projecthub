# Changelog

## v0.1 — Alpha (unreleased)

Initial release. Provides the smallest useful unit: labeled project-to-Space mapping and one-click Space switching.

### Added

- Menu bar app (AppKit `NSStatusItem`) showing a list of projects with their Space numbers.
- Click-to-switch: clicking a project posts a synthesized `Ctrl+N` keystroke to switch macOS Spaces.
- Edit Projects window (SwiftUI) with add, remove, rename, and Space reassignment.
- Persistent storage in `~/Library/Application Support/ProjectHub/projects.json`, forward-compatible with future schema fields.
- Active-Space highlighting via private CoreGraphics (`CGSMainConnectionID` / `CGSCopyManagedDisplaySpaces`), degrading silently if unavailable.
- Onboarding window with deep links to the three required macOS settings panes.
- Accessibility permission detection, with a banner in the editor until granted.
- `install.sh` / `uninstall.sh` and a LaunchAgent for login auto-start.
