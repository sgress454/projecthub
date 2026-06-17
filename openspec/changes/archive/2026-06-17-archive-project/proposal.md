## Why

When a project ends — PR merged, repo archived, contract finished — the user wants to set it aside without losing the work product accumulated against it (name, links, GitHub issues/PRs, OpenSpec change, summary). Today the only option is Delete, which discards everything.

This proposal adds an Archive action: the project is hidden from the menu bar and moved to a collapsed "Archived" section in Edit Projects. Its Space assignment, path, and Claude monitoring are stripped, but identity and metadata are preserved. Restore clears the flag and returns the project to an unassigned-active state.

Auto-closing the project's windows when archiving is convenient but not load-bearing, and it carries enough independent risk (private CGS calls, AX behavior on Electron apps, timeout tuning) to deserve its own change. It is deferred to a future `auto-close-project-windows` change.

## What Changes

- Add `archived: Bool` (default false) and `archived_at: ISO8601 String?` (default nil) per project, round-tripped through `projects.json`.
- Add an "Archive" button per row in the active project list in Edit Projects.
- Archiving sets `archived = true` and `archived_at = now`, and strips `space`, `space_id64`, `path`, and `claude_enabled`. Identity and metadata (`id`, `name`, `github_issues`, `github_prs`, `links`, `openspec_change`, `summary`) are preserved.
- Add an "Archived" disclosure section below the active list, collapsed by default, ordered by `archived_at` descending (last-archived-first).
- Add a "Restore" button on archived rows that clears `archived` and `archived_at`, returning the project to an unassigned-active state. The user assigns a Space using the same Space picker as any other unassigned project.
- Filter archived projects out of the menu bar list.

## Capabilities

### Modified Capabilities
- `projecthub`: Storage gains `archived` and `archived_at` fields. Menu bar list filters out archived projects. Edit Projects gains an Archive button per row, an Archived disclosure section, and a Restore button per archived row.

## Impact

- **Code:** `Sources/ProjectHubKit/Project.swift` (fields + storage round-trip + archive/restore helpers), `Sources/ProjectHubKit/ProjectStore.swift` (active/archived partition for views), `Sources/EditProjectsWindow.swift` (Archive button, Archived section, Restore button).
- **APIs:** None new.
- **Dependencies:** No new third-party dependencies.
- **Storage:** `projects.json` gains `archived: bool` (default false) and `archived_at: string?` per project. Both are additive; older binaries round-trip them through the extras bucket.
- **Depends on:** `stable-space-tracking` — Restore returns a project to the unassigned-active state defined by that capability.
- **User-visible:** New per-row Archive button in Edit Projects, new Archived section, Restore button on archived rows.
- **Out of scope:** Auto-closing windows on the project's Space when archiving (deferred to `auto-close-project-windows`); programmatic Space removal; Restore-time window reopening or app relaunching.
