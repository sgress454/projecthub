## Context

ProjectHub is a macOS menu bar app (AppKit + SwiftUI) that maps projects to Spaces and shows Claude session state per project. The menu is built with `NSMenu` + custom `NSView`-backed `NSMenuItem`s (`ProjectRowView`). Data is persisted as JSON in `~/Library/Application Support/ProjectHub/projects.json` with a forward-compatible schema (unknown fields round-tripped). The app already has a runtime dependency on the `claude` CLI for stop-event classification.

This change adds per-project metadata (GitHub issues, PRs, links, OpenSpec association), a submenu on each project row in the menu bar, background GitHub polling, and an AI-generated summary per project.

## Goals / Non-Goals

**Goals:**
- Every project row in the menu bar has a submenu with GitHub links, other links, and an AI summary
- Click-to-switch-spaces still works; submenu opens on hover/arrow
- PRs are auto-discovered by branch; issues and other links are manually managed
- OpenSpec change is auto-detected when unambiguous, manually linked otherwise
- Summary regenerates when underlying data changes, not on a timer
- Graceful degradation when `gh` or `claude` CLI is absent

**Non-Goals:**
- GitHub webhook / push notification integration (we poll)
- Bidirectional GitHub sync (we read only)
- PR review or issue management from within ProjectHub
- Summary generation using the Anthropic API directly (we shell out to `claude` CLI)
- Auto-linking GitHub issues from branch names or PR descriptions

## Decisions

### 1. Submenu via NSMenuItem.submenu on custom-view items

NSMenu supports submenus natively — set `item.submenu` to an `NSMenu` and the system handles hover/arrow/disclosure. The question is whether this works when the parent item uses a custom `view` (`ProjectRowView`).

**It does.** When `NSMenuItem.view` is set, the system still respects `.submenu` — it renders the disclosure arrow and opens the submenu on hover. The parent item's `action` is not sent (custom-view items don't fire actions anyway), so we continue handling click-to-switch via `mouseUp` in the custom view, same as today.

**Alternative considered:** Building a fake submenu with nested views or a popover. Rejected — fighting NSMenu is fragile and we'd lose native submenu behavior (positioning, keyboard nav, dismiss).

### 2. Submenu content built on rebuildMenu()

The submenu for each project is constructed during `rebuildMenu()` in `AppDelegate`, which already runs on every relevant state change. Submenu items are plain `NSMenuItem`s with `action` handlers that call `NSWorkspace.shared.open(url)` to open links in the default browser.

The AI summary is a non-clickable `NSMenuItem` with a multi-line custom view (word-wrapped `NSTextField`). Constrained to ~280pt width to match the menu.

### 3. Metadata stored directly on Project model

New optional fields on `Project`:

```swift
public var githubIssues: [URL]           // manually added
public var githubPRs: [URL]              // auto-discovered + manually added
public var links: [LabeledLink]          // {url: URL, label: String}
public var openspecChange: String?        // e.g. "add-dark-mode"
public var summary: String?              // cached AI output
```

`LabeledLink` is a simple struct. All new fields serialize to/from the existing JSON dictionary pattern (`toDictionary` / `fromDictionary`), and are absent/empty on v2 files.

**Alternative considered:** Separate `ProjectMetadata` store. Rejected — adds file coordination complexity for no real benefit. The data is small and tightly coupled to the project identity.

### 4. GitHub sync via `gh` CLI in a background actor

A new `GitHubSync` class (or actor) that:
1. For each project with a `path`, runs `git -C <path> branch --show-current` to get the branch.
2. Runs `gh pr list --head <branch> --json number,title,url,state,reviewDecision --repo <remote>` to find PRs.
3. For open PRs, runs `gh pr view <number> --json comments,reviews --repo <remote>` to count unresolved reviewer comments (comments not authored by the PR author that aren't resolved).
4. Updates `project.githubPRs` with discovered PR URLs (merged with any manually-added ones, which are flagged so auto-discovery doesn't remove them).
5. Fires on a timer — every 5 minutes when there are open PRs on any project, every 15 minutes otherwise.

The remote is derived from `git -C <path> remote get-url origin`. If `gh` is not installed, GitHub sync is silently disabled.

**PR data caching:** The raw PR metadata (title, state, comment counts) needs to live somewhere for the submenu to display it without re-fetching. A lightweight in-memory `GitHubPRInfo` cache keyed by PR URL, populated during sync and read during `rebuildMenu()`. Not persisted to disk — rebuilt on each sync cycle.

### 5. OpenSpec change auto-detection

On project load and after any metadata edit, scan `<project.path>/openspec/changes/` (resolving symlinks). If exactly one non-archive directory exists, auto-populate `openspecChange`. If zero or multiple exist, leave it nil (user can set manually). The user can always override via the metadata modal.

### 6. AI summary generation via Claude CLI

A `SummaryGenerator` that:
1. Triggers when: GitHub sync completes with changes, a link is manually added/removed, or OpenSpec change is linked/updated.
2. Gathers context: `git -C <path> log --oneline -20`, linked issue titles (from `gh issue view`), open PR titles + unresolved comment counts, and if an OpenSpec change is linked, reads `proposal.md` and `tasks.md`.
3. Shells out to `claude -p` with a prompt like: "You are summarizing the current state of a software project for a developer's menu bar dashboard. Be brief (2-3 sentences max). Include: the project goal if known, what's actively happening, and anything that needs attention (open PR comments, blocked tasks)." Appends the gathered context.
4. Caches the result in `project.summary`. Persisted to disk so it survives restart.
5. If `claude` CLI is absent or the call fails, sets summary to nil (submenu shows the fallback message).

**Debouncing:** Multiple triggers in quick succession (e.g., GitHub sync updates 3 PRs) are coalesced with a 5-second debounce before invoking Claude.

### 7. Metadata edit modal

A new SwiftUI sheet presented from the Edit Projects window. Each project row gets a small info button (ⓘ) that opens the modal. The modal has sections:

- **GitHub Issues**: List of URLs with delete buttons, plus an "Add" text field. On add, we run `gh issue view <url> --json title` to fetch the title for display.
- **Pull Requests**: Shows auto-discovered PRs (marked with ⚡, not deletable) and manually added PRs. Manual add via URL text field.
- **Links**: Label + URL pairs with add/delete.
- **OpenSpec Change**: Dropdown populated by scanning `<path>/openspec/changes/`, plus a "None" option. Shows auto-detected value with option to override.

### 8. Schema version 3

The `projects.json` `version` field becomes `3`. v2 files load without error — the new fields simply default to empty/nil. The existing `extraFields` pattern on `Project` already handles forward-compatible round-tripping for fields we don't recognize.

## Risks / Trade-offs

**`gh` CLI availability** — Not all users will have `gh` installed. Mitigation: GitHub features degrade gracefully (no PRs shown, no issue titles fetched). The metadata modal shows a hint: "Install the GitHub CLI (`gh`) for PR auto-discovery."

**`gh` auth state** — `gh` requires authentication. If not authed, commands fail. Mitigation: detect `gh auth status` failure and show a one-line warning in the metadata modal, similar to the existing `claude` CLI warning.

**GitHub API rate limits** — With many projects and frequent polling, we could hit rate limits. Mitigation: 5/15-minute polling intervals are conservative. `gh` uses the user's token, which has 5000 req/hr. Even 20 projects polling every 5 minutes is ~240 req/hr.

**Summary quality/cost** — Shelling out to `claude -p` on every data change has a cost (API usage) and latency (1-3s). Mitigation: debouncing, and only regenerating when data actually changed (not just on every poll cycle). The summary is cached so the menu always renders instantly.

**Submenu on every row** — Even projects with no metadata get a submenu. This adds visual weight (the disclosure arrow). Mitigation: the arrow is standard NSMenu chrome, users expect it. The submenu always has value because the summary draws from git log even without explicit links.

**OpenSpec symlink resolution** — In the Fleet worktree setup, `openspec/` is a symlink. Scanning it finds all changes across all projects, so auto-detection only works when there's exactly one non-archive change. For Fleet, this means manual linking is the norm. Mitigation: the dropdown makes this one click.
