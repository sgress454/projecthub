## Why

Heavy concurrent use of Claude Code across 3–5 projects has made workflow management painful. Assets for any given project are scattered across iTerm tabs, VSCode windows, Chrome tabs, and CI/PR/design URLs, with no single unit of organization that is "this project." Two pains dominate:

1. **Asset organization per project** — context-switching between projects requires mentally re-locating the right terminal tab, editor window, and browser tabs.
2. **Per-project state visibility** — no quick way to see which project is waiting on Claude, on a code review, or on CI.

Adopting macOS Spaces (one per project) solves most of pain #1 by teleporting asset sets via a single keystroke. The remaining gap is that macOS does not let you label Spaces, so "which Space is which project?" becomes a memorization problem that breaks down past 2–3 projects.

ProjectHub v0.1 closes that gap: a menu bar app that maps project names to Space numbers and lets the user click a project name to switch to its Space. This is the smallest useful unit; it unblocks real daily use of Spaces as the organization primitive and creates the platform for future state-visibility features (Claude status, git, PR, CI) without committing to their design yet.

## What Changes

- New macOS menu bar app (Swift + SwiftUI, `MenuBarExtra`).
- User-editable list of projects, each with a name and an assigned Space number (1–9).
- Clicking a project in the menu bar triggers a synthesized `Ctrl+N` keystroke to switch Spaces.
- An "Edit Projects…" window to add, remove, rename, and reassign projects.
- Local JSON storage for the project list.
- Optional highlight of the currently active Space via a private CoreGraphics call, degrading gracefully if unavailable.

## Capabilities

### New Capabilities

- `projecthub`: Menu bar–based project-to-Space mapping and switching for macOS, including project list management and optional active-Space detection.

### Modified Capabilities

None (new project).

## Impact

- New repository at `~/Development/projecthub/`.
- New dependency on macOS Accessibility permission (required for synthesized keystrokes).
- No cross-project changes; ProjectHub is a standalone app.
- Future ProjectHub changes (v0.2+) will extend the same `projecthub` capability with state monitoring, asset raising, and integrations.
