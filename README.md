# ProjectHub

A macOS menu bar app that labels your Spaces by project name, switches to a project's Space in one click, and surfaces per-project context — Claude Code session state, GitHub PRs/issues, an AI status summary, and running Fleet/webpack processes — so you know at a glance which project needs your attention.

macOS lets you assign one Space per project (and teleport between them with `Ctrl+N`), but does not let you *label* Spaces — so "which Space is which?" breaks down past two or three projects. And without a signal, a permission prompt or a Claude question in another Space can sit unaddressed for an hour. ProjectHub closes both gaps, then adds the per-project context you'd otherwise hunt across Spaces and terminal windows to find.

## What it does

### Space switching

- Labeled list of projects in the menu bar; click a project to switch to its Space.
- Highlights the row for the currently active Space.
- Optionally shows the active project's name in the menu bar itself, shrinking the title (full name → end-truncated → icon-only) so the status item never gets hidden when the menu bar runs out of room.
- Spaces 1–16 are supported. Each project's Space is tracked by a stable identifier, so reordering, inserting, or removing Spaces in Mission Control re-derives the right "Space N" automatically. If a project's Space is removed, its row renders disabled until you reassign it.
- Edit your project list in a window — add, rename, remove, reassign, archive, and restore — with changes saved automatically. Archived projects are tucked into a collapsed section and excluded from the menu.

### Claude status

- Per-project traffic-light state driven by Claude Code hook events:
  - 🟢 **Green** — nothing pending.
  - 🟡 **Yellow** — begs for your attention (Claude finished with substantive output).
  - 🔴 **Red** — Claude is waiting on you (permission prompt or question).
  - ⏳ **Spinner** — Claude is mid-turn.
- A count badge on the menu bar icon shows how many projects are yellow or red (tinted red if any are red, yellow otherwise). The icon also pulses while any project has Claude mid-turn.
- Switching to a project's Space downgrades red → yellow ("I've seen it"). Answering Claude clears to green.
- Per-project opt-in: set a path + flip a switch in Edit Projects. Scratchpad Spaces stay silent.

### Per-project submenu

Hovering a project row opens a submenu with that project's context:

- **GitHub issues & PRs** — linked issues and PRs with titles; PRs surface unresolved review-comment counts. Click to open in the browser.
- **Links** — arbitrary labeled URLs you attach to the project.
- **Directory** — the assigned folder; click to copy its absolute path.
- **AI summary** — a cached 2–3 sentence "where does this project stand?" generated from the project's OpenSpec plan, git activity, and PR status via the `claude` CLI.

You attach issues, PRs, links, and an OpenSpec change through a per-project metadata editor.

### GitHub sync

Background PR auto-discovery: for each project with a git repo, ProjectHub queries the `gh` CLI for PRs on the current branch and caches their title, state, and unresolved-comment count, on an adaptive polling cadence. Degrades silently when `gh` is missing or unauthenticated.

### Open in terminal

Each project row has a trailing terminal icon. Click it to open the project's directory in your configured terminal (iTerm2 or Terminal.app) without switching Spaces. The icon is greyed out when the project has no path or the configured terminal isn't installed.

### Fleet process indicators

For Fleet development, ProjectHub scans running processes and tags the owning project's row with:

- 🌐 — a Fleet server (`*/build/fleet serve`); hover shows the listening port.
- 🎨 — a webpack build (`webpack --progress`/`--watch`); hover shows the output directory.

Clicking an indicator posts your configured iTerm hotkey-window keystroke to bring the Fleet console to the front from any Space.

## Requirements

- macOS 13 or later
- Accessibility permission (granted on first launch)
- Two macOS settings:
  - **System Settings → Keyboard → Keyboard Shortcuts → Mission Control:** enable "Switch to Desktop 1" through 9. Spaces 10–12 use `Control+0`, `Control+-`, `Control+=` by convention; Spaces 13–16 require a shortcut you assign yourself.
  - **System Settings → Desktop & Dock → Mission Control:** disable "Automatically rearrange Spaces based on most recent use"
- Optional CLI dependencies (each feature degrades gracefully if its tool is absent):
  - `claude` on your `$PATH` — Claude status classification and AI summaries. Without it, Stop events default to red (safe bias).
  - `gh`, authenticated — GitHub PR auto-discovery and issue/PR titles.

The in-app Setup Guide walks you through the Space-switching prerequisites on first launch.

## Install

```bash
git clone <this-repo> ~/Development/projecthub
cd ~/Development/projecthub
bash install.sh
```

This builds a release binary to `~/.local/bin/projecthub`, signs it with a stable self-signed identity (so the Accessibility grant survives rebuilds), and registers a LaunchAgent so it starts on login.

## Enabling Claude status

1. Open **Edit Projects…** from the menu bar.
2. For each project you want monitored, click **Set path…** and choose its repo folder.
3. Flip the per-project Claude toggle on (disabled until the path is set).
4. Flip the global **Claude status monitoring** toggle at the top — review the preview of changes to `~/.claude/settings.json`, then confirm.

That writes a small bash hook into `~/.claude/settings.json` (for the `Stop`, `Notification`, `UserPromptSubmit`, and `PostToolUse` events) that appends events to `~/Library/Application Support/ProjectHub/events.jsonl`. ProjectHub watches that file and updates the menu.

Flip the global toggle off any time to remove the hook. Your own hooks and settings are preserved.

## Preferences

Open **Preferences…** from the menu bar's right-click context menu or from the Edit Projects window:

- **Terminal application** — iTerm2 or Terminal.app, used by the open-in-terminal control. Defaults on first launch to iTerm2 if installed, otherwise Terminal.app.
- **iTerm hotkey-window keystroke** — record the global hotkey you've bound in iTerm2 to summon your hotkey window, so clicking a Fleet/webpack indicator can bring it forward.

Preferences are saved immediately and persisted to `~/Library/Application Support/ProjectHub/preferences.json`.

## State machine

| From state       | Trigger                               | To state            |
|------------------|----------------------------------------|---------------------|
| any              | `Notification` (permission prompt)     | 🔴 Red              |
| any              | Stop + classifier = QUESTION           | 🔴 Red              |
| any              | Stop + classifier = REPORT             | 🟡 Yellow           |
| any              | Stop + classifier = DONE               | 🟢 Green            |
| any              | Stop + classifier failure (e.g. no CLI)| 🔴 Red (safe bias) |
| any              | `UserPromptSubmit` (you replied)       | 🟢 Green + ⏳       |
| any              | `PreToolUse` (permission approved)     | 🟢 Green + ⏳       |
| any              | `PostToolUse` (tool finished)          | 🟢 Green + ⏳       |
| 🔴 Red           | Active Space becomes this project      | 🟡 Yellow           |
| 🔴 Red / 🟡 Yellow | User clicks the × dismiss control    | 🟢 Green            |

The state only ever changes on one of these triggers — no silent timeouts, no decay.

## Privacy

ProjectHub has no analytics, telemetry, or network calls of its own. Data leaves your machine only through the CLIs you opt into, using your existing auth:

- **`claude`** — when Claude status is enabled, the final assistant message of each Stop event is sent to `claude -p` to classify it as QUESTION / REPORT / DONE. AI summaries send project context (OpenSpec proposal, recent git log, PR status) to `claude -p`. If `claude` isn't installed or fails, the project is flagged red (conservatively) and no call is made.
- **`gh`** — GitHub sync queries your repositories through the `gh` CLI's GitHub authentication.

## Uninstall

```bash
bash uninstall.sh
```

Your `projects.json` and `preferences.json` are preserved at `~/Library/Application Support/ProjectHub/`. If you had Claude status enabled, disable it from Edit Projects **before** uninstalling so `~/.claude/settings.json` is cleaned up — or manually remove lines containing `# projecthub-managed`.

## Storage

| Location                                                     | What                                   |
|--------------------------------------------------------------|----------------------------------------|
| `~/Library/Application Support/ProjectHub/projects.json`     | Project list + metadata (schema v3)    |
| `~/Library/Application Support/ProjectHub/preferences.json`  | User-level app preferences (v1)        |
| `~/Library/Application Support/ProjectHub/events.jsonl`      | Append-only Claude hook event log      |
| `~/Library/Application Support/ProjectHub/hooks/`            | The installed hook bash script         |
| `~/.claude/settings.json`                                    | Mutated (opt-in) to register the hook  |

`projects.json` is forward-compatible — unknown fields are round-tripped on read/write, so future versions can add metadata without breaking older binaries. Files written by earlier schema versions (v1, v2) load without migration. `preferences.json` follows the same idiom.

## Development

Swift Package Manager project split into a library (`ProjectHubKit`, pure logic with a test target) and an executable (`ProjectHub`, AppKit + SwiftUI UI).

```bash
swift build             # debug
swift build -c release  # release
swift test              # run the library test suite
.build/debug/ProjectHub # run directly (no LaunchAgent)
```

Menu bar surface uses AppKit (`NSStatusItem`, `NSMenu`, custom views for rows); Edit Projects, the metadata editor, Preferences, and Onboarding use SwiftUI via `NSHostingController`.

## Design

See `openspec/` for the proposals, design docs, and task breakdowns. Durable specs live in `openspec/specs/` (one capability per directory — `projecthub`, `project-submenu`, `project-metadata`, `ai-summary`, `github-sync`, `app-preferences`, `fleet-process-indicators`). The current active change — if any — is in `openspec/changes/<name>/`.
