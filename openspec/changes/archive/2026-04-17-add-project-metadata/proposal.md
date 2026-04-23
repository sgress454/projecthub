## Why

ProjectHub tells you *which project needs attention* but not *what's going on* with it. To get context you have to leave the menu bar and open GitHub, check PR comments, remember which branch maps to which issue, etc. — exactly the kind of context-switching ProjectHub was built to eliminate.

## What Changes

- **NEW** per-project metadata: manually linked GitHub issues, auto-discovered + manually linked GitHub PRs, arbitrary labeled links (Figma, Notion, etc.), and an OpenSpec change association (auto-detected from `<path>/openspec/changes/` when exactly one exists, with manual override).
- **NEW** metadata editing modal in the Edit Projects window, per project.
- **NEW** submenu on each project row in the menu bar dropdown. Hover/arrow opens the submenu (issues, PRs, links, AI summary); click still switches Spaces. Every project gets a submenu.
- **NEW** GitHub PR auto-discovery: periodic polling via `gh pr list` using the project's current branch, plus comment counts via `gh pr view`.
- **NEW** AI-generated project summary cached per project, regenerated on data change (git activity, GH metadata changes, link edits). Summary draws on git log, PR/issue state, and OpenSpec proposal+tasks when linked. Falls back to "No summary yet — attach GitHub issues or start an OpenSpec plan!" when no context is available.
- **MODIFIED** storage schema bumped to v3 to accommodate new per-project fields. v2 files load without error; new fields take empty/nil defaults.

## Capabilities

### New Capabilities

- `project-metadata`: Data model, persistence, and editing UI for per-project GitHub issues, PRs, arbitrary links, and OpenSpec change association.
- `project-submenu`: Menu bar submenu per project row — hover to open, click to switch Spaces — displaying linked issues, PRs, other links, and the cached AI summary.
- `github-sync`: Background auto-discovery of PRs by branch via `gh` CLI, periodic polling for PR status and unresolved reviewer comment counts.
- `ai-summary`: AI-generated project summary pipeline — triggered by data changes, produced via Claude CLI, cached on the project.

### Modified Capabilities

- `projecthub`: Storage schema version bumped to 3; Project model extended with metadata fields. Existing requirements (persistence, round-tripping unknown fields) apply to the new fields.

## Impact

- **Data model**: `Project` gains new optional fields. `ProjectStore` schema version incremented. Forward-compatibility guarantee (unknown-field round-tripping) continues to apply.
- **UI**: Menu bar rows gain a submenu arrow and a new interaction mode (hover vs click). Edit Projects window gains a per-row metadata button and a new modal.
- **Dependencies**: Runtime dependency on `gh` CLI for GitHub integration (graceful degradation when absent). Runtime dependency on `claude` CLI for summary generation (already present for classification).
- **Network**: Periodic `gh` calls hit the GitHub API. No new direct network calls from the app itself.
