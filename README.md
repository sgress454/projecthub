# ProjectHub

A macOS menu bar app that labels your Spaces by project name and switches to a project's Space in one click.

macOS lets you assign one Space per project (and teleport between them with `Ctrl+N`), but does not let you *label* Spaces — so "which Space is which?" breaks down past two or three projects. ProjectHub closes that gap.

## What it does (v0.1)

- Shows a labeled list of your projects in the menu bar, each with its Space number.
- Click a project to switch to its Space.
- Highlights the row for the currently active Space.
- Edit your project list in a small window; changes save automatically.

Out of scope for v0.1 (coming later): Claude Code activity state, git / PR / CI status, raising terminal + editor + browser windows, Arc integration.

## Requirements

- macOS 13 or later
- Accessibility permission (granted on first launch)
- Two macOS settings:
  - **System Settings → Keyboard → Keyboard Shortcuts → Mission Control:** enable "Switch to Desktop 1" through 9
  - **System Settings → Desktop & Dock → Mission Control:** disable "Automatically rearrange Spaces based on most recent use"

The in-app Setup Guide walks you through all three on first launch.

## Install

```bash
git clone <this-repo> ~/Development/projecthub
cd ~/Development/projecthub
bash install.sh
```

This builds a release binary to `~/.local/bin/projecthub` and registers a LaunchAgent so it starts on login.

## Uninstall

```bash
bash uninstall.sh
```

Your `projects.json` is preserved at `~/Library/Application Support/ProjectHub/`.

## Storage

Project list lives at `~/Library/Application Support/ProjectHub/projects.json`. Forward-compatible: unknown fields are preserved across reads and writes, so future versions can add metadata without breaking v0.1.

## Development

Built with Swift Package Manager. Menu bar surface uses AppKit; editor and onboarding windows use SwiftUI via `NSHostingController`.

```bash
swift build            # debug
swift build -c release # release
.build/debug/ProjectHub   # run directly (no LaunchAgent)
```

## Design

See `openspec/changes/add-projecthub-alpha/` for the full proposal, design doc (including the v0.2–v0.6 roadmap), and task breakdown. Durable specs live in `openspec/specs/projecthub/` once the change is archived.
