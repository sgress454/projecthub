## Context

### Where v0.1 landed

ProjectHub v0.1 ships a menu bar app that maps project names to macOS Spaces and switches to a project's Space on click. Daily use has confirmed the premise works: Spaces are a viable organization primitive at 3–5 projects when they are labeled and clickable. The "which Space is which project?" problem is solved.

Two implementation details from the alpha matter for v0.2:

1. **Active-Space observation is event-driven.** The alpha's `design.md` sketched a 1s-poll Timer (§4.3), but the shipped code in `Sources/AppDelegate.swift:35-44` uses `NSWorkspace.activeSpaceDidChangeNotification`. v0.2 builds on this — no new polling required.
2. **JSON storage is forward-compatible.** Alpha D3 specified that `projects.json` preserves unknown per-project fields on read/write. This means v0.2 schema additions (`path`, `claude_enabled`) need no migration.

### The next pain

From the alpha's design §Problem decomposition, the user identified five failure modes under "workflow chaos." v0.1 tackles #1 (attention routing) partially — the menu bar click gets you to the right Space, but you still have to look at every project to decide which one needs you. The biting problem now is **#2 (stall detection): is Claude waiting on me and I don't know?**

Concretely: Claude asks for permission in a project sitting in Space 4. The user is heads-down in Space 1. Minutes or hours pass. The permission was actually trivial. This is the failure mode v0.2 eliminates.

## Goals / Non-Goals

**Goals:**

- Each project has a discrete status (green / yellow / red) that reflects Claude's current need for the user.
- A `working` sub-state is visible per row while Claude is mid-turn.
- A menu bar badge surfaces the count of non-green projects without opening the menu.
- State is driven by Claude Code hook events, not polling or transcript tailing.
- `Stop` events are classified three ways (QUESTION / REPORT / DONE) — completion is distinguished from questions and from substantive reports that beg attention.
- Install and uninstall of the Claude Code hook are reversible and user-initiated.
- Opt-in per project via a `claude_enabled` flag so scratchpad or exploratory Spaces stay silent.

**Non-Goals (v0.2):**

- Git status, branch state, dirty-tree detection. (Deferred — different signal source, different cadence.)
- PR / CI / GitHub integration. (v0.3.)
- Asset raising (iTerm windows, VSCode windows, Chrome tabs). (v0.5.)
- Transcript replay, history browsing, or analytics.
- Cross-machine sync of state.
- Native notifications (banners, sounds). The badge is the only ambient signal.
- Multi-session-per-project handling. One Claude session per project for v0.2; last event wins on collision.
- A heartbeat / "Claude is stalled" state. `working` shows for as long as Claude says it's working.

## Decisions

### D1. Three-state model with a `working` sub-state

**Chosen:** States are `green` (nothing pending), `yellow` (begs for attention), `red` (Claude is waiting on you). `working` is a transient sub-state that renders as a spinner in place of the colored dot.

**Transitions:**

```
   Event                                       New state
   ─────────────────────────────────────────────────────
   Notification                                red, working=false
   Stop + classifier=QUESTION                  red, working=false
   Stop + classifier=REPORT                    yellow, working=false
   Stop + classifier=DONE                      green, working=false
   UserPromptSubmit                            green, working=true
   PreToolUse                                  green, working=true*
   PostToolUse                                 green, working=true*
   Active Space becomes this project AND red   yellow
   Active Space becomes this project AND !red  unchanged
```

\* Both `PreToolUse` and `PostToolUse` downgrade to green. If Claude
is about to run, or has just finished running, a tool — Claude is
acting on the user's behalf and the user isn't blocking anything.
`PreToolUse` is what makes permission approval feel instant: the
moment the user clicks approve, `PreToolUse` fires with the
permission granted and the tool about to execute, so the red clears
immediately rather than waiting for the tool to finish (`PostToolUse`).

**Stickiness:** State only changes on explicit triggers above. No time-based decay. No optimistic flips. Between a `UserPromptSubmit` and the next `Stop`, the row sits in `working`; if that takes 30 seconds or 30 minutes, that's fine.

**Rejected:** A two-state "needs me / doesn't" model. It collapses "I haven't seen this" into "I've seen it and haven't acted," which loses the useful "yellow" bucket where the user is aware of something but deliberately hasn't responded yet.

**Why:** Three-state preserves the distinction between "unseen" (red demands your attention) and "seen but not yet resolved" (yellow acknowledges you know), cheaply.

### D2. Three-way classifier via `claude -p`

**Chosen:** On `Stop`, read the last assistant message from the transcript and pipe it to `claude -p` with a fixed prompt returning one of QUESTION / REPORT / DONE.

**Prompt shape:**

> You are classifying the FINAL assistant message in a Claude Code conversation to decide whether the user needs to look at it. Return exactly one of: `QUESTION` (message asks the user to decide, approve, choose, or answer — includes explicit questions AND cases where Claude is blocked and needs direction), `REPORT` (message presents substantive findings, analysis, or multiple options — worth attention even though Claude isn't blocked), `DONE` (completion report with no open question and no content that demands review). Message: `<<<{final_message}>>>` Answer (one word):

**Rejected:**

- **Heuristic-only regex** (matching `?`, "should I", "would you like"). Too brittle, especially for the REPORT case which has no linguistic tell.
- **Direct Anthropic API to Haiku.** Would require the user to configure `ANTHROPIC_API_KEY` separately. ProjectHub's audience is already authed through the `claude` CLI.
- **Long-lived classifier subprocess.** Premature optimization. First measure actual cold-start latency.

**Why `claude -p`:** Rides on the user's existing auth and plan, no separate setup. ~500ms cold latency is acceptable because classification is async relative to the hook (the hook just appends the event; classification happens inside ProjectHub as it processes the log).

**Bias:** Default to **RED** on parse failure, timeout, or missing CLI. False-positive RED is a minor nag; false-negative GREEN defeats the entire feature (the user misses a blocked Claude).

### D3. Push via a single global hook, not transcript tailing

**Chosen:** Register one global hook in `~/.claude/settings.json` for the four relevant events (`Stop`, `Notification`, `UserPromptSubmit`, `PostToolUse`). The hook is a ~5-line bash script that appends a single JSON line per event to `~/Library/Application Support/ProjectHub/events.jsonl`. ProjectHub watches the file via `DispatchSourceFileSystemObject`.

```
  Hook event                  Hook action
  ─────────────────────────────────────────────────────────────
  Stop                        append { ts, cwd, transcript, "stop" }
  Notification                append { ts, cwd, "notification" }
  UserPromptSubmit            append { ts, cwd, "user_prompt" }
  PostToolUse                 append { ts, cwd, "post_tool" }
```

**Rejected:**

- **Per-project transcript jsonl tailing.** Couples ProjectHub to Claude's transcript schema (which evolves), requires a file watcher per project, and needs heuristics to parse message roles / tool states.
- **Per-project hooks** in each repo's `.claude/settings.json`. Multiplies install friction and creates drift across repos.
- **Unix domain socket between hook and app.** Adds a moving part for no real benefit — file appends are already atomic per write, and a file survives ProjectHub restarts.

**Why:** One hook, one file, one watcher. Decoupled from Claude's transcript internals (only the four hook event names matter). Atomic appends survive concurrent Claude sessions from multiple projects at once.

### D4. Hook install is opt-in, reversible, and shows a preview

**Chosen:** A single global "Enable Claude status" toggle (not per-project) in the Edit Projects window. Clicking it:

1. Reads `~/.claude/settings.json`.
2. Computes the merged JSON with ProjectHub's four hook entries added. Each entry is tagged with a recognizable marker (e.g., a known `"__projecthub"` key or comment-style marker we can round-trip).
3. Displays a diff preview in a modal.
4. On confirm, writes atomically (write to temp, `rename(2)` over the original).

Uninstall does the reverse: parse, strip only our tagged entries, write.

**Why:** Writing to a user-owned config file is sensitive. Preview + reversibility builds trust. Merging (not replacing) preserves any hooks the user has already set up — this is a requirement, not a nice-to-have.

### D5. Project ↔ event matching by longest path prefix

**Chosen:** Each project has an optional `path`. On each hook event, match `event.cwd` against all projects' `path` fields and pick the longest prefix match. Projects without a `path` never match.

**Why:** Worktrees share a prefix with their parent repo. A worktree project at `/Users/scott/Development/fleet-worktrees/auth` beats a general "fleet" project at `/Users/scott/Development/fleet` when the cwd is inside the worktree, because its prefix is longer. No special worktree logic; the longest-prefix rule handles it.

**Implication:** Projects intended for state monitoring must have `path` set. Projects without `path` keep working as Space switchers but never go yellow / red. This is desirable for "scratchpad" Spaces.

### D6. Per-project opt-in via `claude_enabled`

**Chosen:** A boolean flag per project (default `false`). When `false`, events for that project's path are ingested but never drive state transitions for that project.

**Why:** Not every project wants monitoring. A scratchpad, a one-off spike, or a throwaway Space shouldn't generate noise. The flag is also the escape hatch if monitoring misbehaves on a specific project — turn it off without reinstalling the hook.

### D7. Active-Space transition reuses the existing notification observer

**Chosen:** The `red → yellow` transition on "active Space becomes this project" is driven by the same `NSWorkspace.activeSpaceDidChangeNotification` observer v0.1 already subscribes to. No new polling.

**Why:** The observer fires for all Space changes — from our click, from Ctrl+N, from trackpad gestures, from Mission Control. Reusing it costs nothing and is already the system of record for "what Space is active." See `Sources/AppDelegate.swift:35-44`.

### D8. Menu bar icon badge composition

**Chosen:** Badge count is the number of projects whose state is red or yellow. Badge color is red if any project is red, otherwise yellow. No badge when zero.

```
  State distribution                Badge
  ─────────────────────────────────────────────
  0 red, 0 yellow                   (none)
  0 red, 2 yellow                   2 (yellow-tinted)
  1 red, 0 yellow                   1 (red-tinted)
  1 red, 2 yellow                   3 (red-tinted — dominant)
```

**Rejected:** Separate red and yellow badges (busy), color-only badge without a number (low information), a separate icon change per state (visual noise).

**Why:** One glance, two pieces of information (urgency level + scope). Matches the alarm-mode-with-richer-detail behavior the user asked for.

### D9. `working` is a row-level sub-state only

**Chosen:** The spinner replaces the row's colored dot while the project is in `working`. It does not contribute to the menu bar badge count, and the menu bar icon does not change.

**Why:** `working` is not actionable. Claude is doing something; the user doesn't need to look. Surfacing `working` in the badge would dilute its "you have things to handle" meaning.

### D10. Schema bump to `version: 2`, fully backward-compatible

**Chosen:** `projects.json` `version` becomes `2`. `Project` gains two optional fields: `path: String?` and `claude_enabled: Bool` (default `false`). A `settings` object at the top level holds global state, e.g., `claude_hook_installed: Bool`.

```jsonc
{
  "version": 2,
  "settings": {
    "claude_hook_installed": true
  },
  "projects": [
    {
      "name": "fleet-auth-refactor",
      "space": 3,
      "path": "/Users/scott/Development/fleet-worktrees/auth-refactor",
      "claude_enabled": true
    }
  ]
}
```

**Why:** v0.1 files (`version: 1`) decode cleanly because new fields are optional with defaults. Alpha D3's forward-compatible decoding was designed for exactly this. No migration routine needed.

### D11. State reconstruction on restart via event-log replay

**Chosen:** On startup, ProjectHub replays the tail of `events.jsonl` to reconstruct each project's current state before rendering the menu. No separate persisted state file.

**Why:** The event log is authoritative — any derived state can be rebuilt from it. This avoids cache-invalidation bugs (stored state disagreeing with the log) and makes the event log the single source of truth.

**How much to replay:** Scan backwards until we've seen a terminal event for each known project (`Stop` or `Notification`), or until we hit a configurable lookback window (e.g., 24 hours), whichever is first.

## Risks / Trade-offs

- **`claude -p` cold-start latency.** Measured expectation ~500ms first invocation, faster on subsequent. During that window, the row sits in its prior state (no flicker). → Acceptable. If it ever bites, consider a keepalive subprocess later.
- **Hook script fragility.** A malformed hook could in principle interfere with Claude Code sessions. → The script begins with `exec >/dev/null 2>&1` so any error is suppressed and the hook cannot block or break Claude.
- **Active-Space notification may miss an event.** macOS has been observed to occasionally drop `activeSpaceDidChangeNotification` in edge cases (fast Space switches, external display reattach). → The red-highlighted row will stay red until the user clicks on it (which opens the menu and triggers a re-read). Acceptable — worst case is "slightly stale RED."
- **Privacy: classifier sends message content through `claude`.** Same privacy posture as the user's normal Claude Code use. → Documented in the Setup Guide. Heuristic-only mode can be added as opt-out if needed.
- **Hook merge conflicts on uninstall.** If the user manually edits `~/.claude/settings.json` after install, our uninstall logic must still surgically remove only ProjectHub-tagged entries. → Tag our entries with a stable marker; uninstall matches on the marker; on mismatch, show a manual-edit dialog instead of silently failing.
- **Ambiguous classifier output.** The REPORT category is linguistically fuzziest. Expect tuning over time. → Prompt is a single string constant, trivial to iterate on.
- **Runaway `working`.** If Claude crashes mid-turn and `Stop` never fires, the spinner is permanent until restart or a new `UserPromptSubmit`. → Acceptable for v0.2. Add a lost-heartbeat timeout later if this happens in practice.

## Migration Plan

1. **v0.1 → v0.2 upgrade is seamless for existing users.** `projects.json` (v1) loads unchanged; `claude_enabled` defaults to `false`, so no project goes yellow / red until the user opts in.
2. **To enable end-to-end state:**
   1. In Edit Projects, set `path` on the projects you want monitored.
   2. Click "Enable Claude status" to install the global hook (preview + confirm).
   3. Toggle the per-project Claude switch on the projects you want monitored.
3. **Rollback:** Click "Enable Claude status" off → hook removed from `~/.claude/settings.json` → all projects revert to green. The app continues working as a Space switcher exactly as v0.1 did.
4. **Downgrade to v0.1 binary is safe.** v0.1 ignores the new fields (forward-compat per alpha D3).

## Open Questions

- **~~Should YELLOW also clear via "dismiss"?~~** Resolved: yes. Added after first real use showed yellow accumulating when reports didn't need a direct reply. Implemented as a per-row × control that appears only when state is yellow; clicking clears to green and closes the menu. Red and green are unaffected — red means Claude is genuinely waiting on the user and must not be dismissible.
- **Multiple concurrent sessions per project.** What if the user runs two `claude` sessions in the same cwd? For v0.2, treat as one project: the latest event wins. Revisit if this becomes a real use case.
- **How aggressively to rotate events.jsonl.** Tentative: rotate at 10MB or daily, keep last 3 files. Tune after observation.

## References

- `Sources/AppDelegate.swift:35-44` — existing event-driven Space observer that v0.2 reuses.
- `openspec/changes/add-projecthub-alpha/design.md` §D3 — forward-compatible JSON storage that enables the schema bump without migration.
- `openspec/changes/add-projecthub-alpha/design.md` §Future Roadmap — original sketch of v0.2 as "State visibility, local-only." This change narrows that to Claude-only; git signals land in a later change.
- Claude Code hooks: `Stop`, `Notification`, `UserPromptSubmit`, `PostToolUse` event types and their payload fields (`cwd`, `session_id`, `transcript_path`, `hook_event_name`).
