## 1. Data model & persistence

- [ ] 1.1 Add `LabeledLink` struct to ProjectHubKit (url: URL, label: String, with dictionary serialization).
- [ ] 1.2 Add metadata fields to `Project`: `githubIssues: [URL]`, `githubPRs` (with manual/auto flag), `links: [LabeledLink]`, `openspecChange: String?`, `summary: String?`.
- [ ] 1.3 Update `Project.toDictionary()` and `Project.fromDictionary()` to serialize/deserialize the new fields. Empty/nil values omitted from JSON.
- [ ] 1.4 Bump `ProjectStore.currentSchemaVersion` to 3.
- [ ] 1.5 Add `ProjectStore` API methods: `setGithubIssues`, `setGithubPRs`, `setLinks`, `setOpenspecChange`, `setSummary`.
- [ ] 1.6 Write tests: v2 JSON loads with metadata fields defaulting to empty/nil; v3 round-trips all metadata fields; unknown fields still preserved.

## 2. Metadata editing modal

- [ ] 2.1 Create `MetadataEditView` (SwiftUI sheet) with sections: GitHub Issues, Pull Requests, Links, OpenSpec Change.
- [ ] 2.2 GitHub Issues section: list of URLs with delete buttons, text field to add. On add, attempt `gh issue view --json title` to fetch title.
- [ ] 2.3 Pull Requests section: display auto-discovered (marked, not deletable) and manual PRs. Text field to add manually.
- [ ] 2.4 Links section: label + URL pairs with add/delete.
- [ ] 2.5 OpenSpec Change section: dropdown populated by scanning `<project.path>/openspec/changes/` for non-archive subdirectories, plus "None" option.
- [ ] 2.6 Add info button (ⓘ) to each project row in `EditProjectsView` that opens the metadata modal.
- [ ] 2.7 Show inline hint when `gh` CLI is not available or not authenticated.

## 3. Menu bar submenu

- [ ] 3.1 In `AppDelegate.rebuildMenu()`, attach an `NSMenu` submenu to each project's `NSMenuItem`.
- [ ] 3.2 Populate submenu sections: Issues (with titles, clickable), PRs (with title/state/comment count, clickable), Links (with labels, clickable), and summary text.
- [ ] 3.3 Summary displayed as non-clickable `NSMenuItem` with word-wrapped custom view (~280pt width).
- [ ] 3.4 Fallback message when no summary and no metadata: "No summary yet — attach GitHub issues or start an OpenSpec plan!"
- [ ] 3.5 Verify click-to-switch still works with submenu attached (test `mouseUp` in `ProjectRowView` alongside `item.submenu`).
- [ ] 3.6 Clickable submenu items open URLs in default browser via `NSWorkspace.shared.open(url)`.

## 4. GitHub sync

- [ ] 4.1 Create `GitHubSync` class with methods to detect `gh` availability and auth status.
- [ ] 4.2 Implement per-project PR discovery: `git branch --show-current` → `gh pr list --head <branch> --json number,title,url,state`.
- [ ] 4.3 Implement PR metadata fetch: `gh pr view <number> --json` to get unresolved reviewer comment counts (excluding PR author's comments).
- [ ] 4.4 In-memory `GitHubPRInfo` cache (keyed by PR URL) with title, state, comment count.
- [ ] 4.5 Polling timer: 5-minute interval when open PRs exist, 15-minute otherwise. Immediate first sync on launch.
- [ ] 4.6 Merge auto-discovered PRs with manually-added PRs on the project (no duplicates, manual PRs not removed by sync).
- [ ] 4.7 After sync, trigger `rebuildMenu()` and notify summary pipeline if data changed.

## 5. OpenSpec auto-detection

- [ ] 5.1 Implement `openspecChange` auto-detection: scan `<project.path>/openspec/changes/` (resolving symlinks), set if exactly one non-archive subdirectory exists.
- [ ] 5.2 Run auto-detection on project load and when `path` changes. Do not override a manually-set value.
- [ ] 5.3 In the metadata modal dropdown, populate choices from the scan results.

## 6. AI summary generation

- [ ] 6.1 Create `SummaryGenerator` class that gathers context for a project: `git log --oneline -20`, linked issue titles, open PR titles + comment counts, and OpenSpec `proposal.md` + `tasks.md` if linked.
- [ ] 6.2 Invoke `claude -p` with a prompt requesting a 2-3 sentence project status summary, passing gathered context.
- [ ] 6.3 Cache result in `project.summary` via `ProjectStore.setSummary`. Persisted to disk.
- [ ] 6.4 Trigger regeneration when: GitHub sync finds changes, metadata is edited, or git activity produces new commits.
- [ ] 6.5 Debounce: coalesce multiple triggers within 5 seconds into a single generation.
- [ ] 6.6 Handle `claude` CLI absence: skip generation, leave summary nil, log warning.

## 7. Integration & validation

- [ ] 7.1 `swift build` — compiles cleanly.
- [ ] 7.2 `swift test` — all existing and new tests pass.
- [ ] 7.3 Smoke test: add metadata to a project, verify submenu shows issues/PRs/links/summary. Click links to confirm browser opens.
- [ ] 7.4 Smoke test: verify click-to-switch still works on rows with submenus.
- [ ] 7.5 Smoke test: verify graceful degradation with `gh` and `claude` absent from PATH.
