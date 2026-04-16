## Why

ProjectHub v0.1 made Spaces usable as the per-project organization primitive, but the next pain is progress visibility: knowing at a glance which projects need attention because Claude is waiting for input or has produced output worth reviewing. Without this, a permission prompt or a question can sit in another Space for an hour before the user notices, which is the exact failure mode ProjectHub is meant to eliminate.

v0.2 closes that gap by tracking a green/yellow/red state per project driven by Claude Code hook events, with a menu bar badge that surfaces the count of projects needing attention without the user having to open the menu.

## What Changes

- **Three-color project state model.** Each project has a status: `green` (nothing pending), `yellow` (begs for attention), `red` (Claude is waiting on the user). A `working` sub-state renders as a spinner on the row while Claude is mid-turn.
- **State transitions driven by Claude Code hook events.** `Notification`, `Stop`, `UserPromptSubmit`, and `PostToolUse` events flow through a single global hook into an append-only event log.
- **Three-way classifier for `Stop` events.** The last assistant message is classified via `claude -p` as QUESTION / REPORT / DONE and mapped to red / yellow / green respectively.
- **Per-project filesystem `path` and `claude_enabled` fields** so ProjectHub can map events to projects and opt specific projects in or out.
- **Opt-in Claude Code hook install flow.** An "Enable Claude status" toggle writes (with preview) a tagged hook entry into `~/.claude/settings.json`; uninstall removes only the entries this app added.
- **Menu bar icon badge.** Count of projects that are red or yellow; red-tinted if any red, else yellow; hidden when zero.
- **Per-row status indicator in the dropdown.** Colored dot for green/yellow/red, spinner for working.
- **Edit Projects window gains** a directory picker for `path`, a per-project "Claude" toggle, and the global hook enable/disable control.

## Capabilities

### New Capabilities

None — all changes extend the existing `projecthub` capability.

### Modified Capabilities

- `projecthub`: adds Claude state monitoring requirements. No existing v0.1 requirements are removed or weakened; the new behavior is additive.

## Impact

- **New optional dependency:** the `claude` CLI on `$PATH` for classification. If absent, projects with Claude status enabled default to red on any `Stop` event (safe-biased degradation).
- **New file:** `~/Library/Application Support/ProjectHub/events.jsonl` (append-only; rotated by size).
- **External file touched:** `~/.claude/settings.json` — only when the user opts in. Reversible via uninstall. Existing hook entries are preserved.
- **Schema bump:** `projects.json` `version` becomes `2`. v0.1 files load without migration because new fields are optional; v0.1 was already forward-compatible per alpha D3.
- **No new macOS permissions** beyond what v0.1 required (Accessibility).
- **Sequencing:** this change assumes `add-projecthub-alpha` has been archived, so the spec deltas here compose cleanly with the canonical `projecthub` spec.
