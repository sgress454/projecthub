# ProjectHub

A macOS menu bar app that labels your Spaces by project name, switches to a project's Space in one click, and surfaces Claude Code session state per-project so you know at a glance which project needs your attention.

macOS lets you assign one Space per project (and teleport between them with `Ctrl+N`), but does not let you *label* Spaces — so "which Space is which?" breaks down past two or three projects. And without a signal, a permission prompt or a Claude question in another Space can sit unaddressed for an hour. ProjectHub closes both gaps.

## What it does

### v0.1 — Space switching

- Labeled list of projects in the menu bar, each with its Space number.
- Click a project to switch to its Space.
- Highlights the row for the currently active Space.
- Edit your project list in a small window; changes save automatically.

### v0.2 — Claude status

- Per-project traffic-light state driven by Claude Code hook events:
  - 🟢 **Green** — nothing pending.
  - 🟡 **Yellow** — begs for your attention (Claude finished with substantive output).
  - 🔴 **Red** — Claude is waiting on you (permission prompt or question).
  - ⏳ **Spinner** — Claude is mid-turn.
- A count badge on the menu bar icon shows how many projects are yellow or red (tinted red if any are red, yellow otherwise). The icon also pulses while any project has Claude mid-turn.
- Switching to a project's Space downgrades red → yellow ("I've seen it"). Answering Claude clears to green.
- Per-project opt-in: set a path + flip a switch in Edit Projects. Scratchpad Spaces stay silent.

Out of scope for now: git status, PR / CI status, raising terminal + editor + browser windows, Arc integration.

## Requirements

- macOS 13 or later
- Accessibility permission (granted on first launch)
- Two macOS settings:
  - **System Settings → Keyboard → Keyboard Shortcuts → Mission Control:** enable "Switch to Desktop 1" through 9
  - **System Settings → Desktop & Dock → Mission Control:** disable "Automatically rearrange Spaces based on most recent use"
- For v0.2 Claude status (optional): the `claude` CLI on your `$PATH`. Without it, Stop events default to red (safe bias).

The in-app Setup Guide walks you through the Space-switching prerequisites on first launch.

## Install

```bash
git clone <this-repo> ~/Development/projecthub
cd ~/Development/projecthub
bash install.sh
```

This builds a release binary to `~/.local/bin/projecthub` and registers a LaunchAgent so it starts on login.

## Enabling Claude status (v0.2)

1. Open **Edit Projects…** from the menu bar.
2. For each project you want monitored, click **Set path…** and choose its repo folder.
3. Flip the per-project Claude toggle on (disabled until the path is set).
4. Flip the global **Claude status monitoring** toggle at the top — review the preview of changes to `~/.claude/settings.json`, then confirm.

That writes a small bash hook into `~/.claude/settings.json` that appends events to `~/Library/Application Support/ProjectHub/events.jsonl`. ProjectHub watches that file and updates the menu.

Flip the global toggle off any time to remove the hook. Your own hooks and settings are preserved.

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

When Claude status is enabled, ProjectHub invokes `claude -p` on the **final assistant message** of each Stop event to classify it as QUESTION / REPORT / DONE. That message content is sent through your existing Claude auth exactly like any other Claude Code session. If `claude` isn't installed or fails, the project is flagged red (conservatively) — no network call is made.

No data leaves your machine except through that `claude` invocation. No analytics, no telemetry, no network calls of our own.

## Uninstall

```bash
bash uninstall.sh
```

Your `projects.json` is preserved at `~/Library/Application Support/ProjectHub/`. If you had Claude status enabled, disable it from Edit Projects **before** uninstalling so `~/.claude/settings.json` is cleaned up — or manually remove lines containing `# projecthub-managed`.

## Storage

| Location                                                     | What                                   |
|--------------------------------------------------------------|----------------------------------------|
| `~/Library/Application Support/ProjectHub/projects.json`     | Project list + global settings (v2)    |
| `~/Library/Application Support/ProjectHub/events.jsonl`      | Append-only Claude hook event log      |
| `~/Library/Application Support/ProjectHub/hooks/`            | The installed hook bash script         |
| `~/.claude/settings.json`                                    | Mutated (opt-in) to register the hook  |

`projects.json` is forward-compatible — unknown fields are round-tripped on read/write, so future versions can add metadata without breaking older binaries.

## Development

Swift Package Manager project split into a library (`ProjectHubKit`, pure logic with a test target) and an executable (`ProjectHub`, AppKit + SwiftUI UI).

```bash
swift build             # debug
swift build -c release  # release
swift test              # run the library test suite
.build/debug/ProjectHub # run directly (no LaunchAgent)
```

Menu bar surface uses AppKit (`NSStatusItem`, `NSMenu`, custom views for rows); Edit Projects and Onboarding use SwiftUI via `NSHostingController`.

## Design

See `openspec/` for the full proposal, design doc (including the v0.2+ roadmap), and task breakdown. Durable specs live in `openspec/specs/projecthub/`. The current active change — if any — is in `openspec/changes/<name>/`.
