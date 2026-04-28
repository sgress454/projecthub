## Context

projecthub already maps projects to Spaces and surfaces per-project state in the menu bar. Project rows currently show name + Space number + a terminal icon, with click handlers that switch to the assigned Space. Each project optionally carries a filesystem `path` (used today for the terminal-open and Claude-monitoring features), which gives us the substrate to attribute running processes to projects.

The user's working pattern: across several projects on different Spaces, exactly one Fleet server (`./build/fleet serve`) and one webpack build (`yarn ... webpack ...`) are typically running, but locating "the live one" requires hunting through Spaces and iTerm windows. The user has separately configured iTerm2 with a hotkey window so that Fleet processes always live in one summonable window — projecthub's role is to (a) tell them which project owns the running processes and (b) provide a fast click-to-summon for that hotkey window.

Existing constraints we mirror:
- **Storage idiom:** versioned JSON, round-trip unknown fields (matches `projects.json` and `preferences.json`).
- **Keystroke-posting idiom:** the Space-switch path uses a `CGEvent` keypress with a precondition check that the corresponding macOS shortcut is bound, surfacing an actionable dialog when it isn't. The new hotkey-window summon mirrors that pattern.

## Goals / Non-Goals

**Goals:**
- Detect running Fleet server / webpack processes and attribute each to at most one project via path matching.
- Render unobtrusive 🌐 / 🎨 indicators on menu bar rows, right-aligned next to the existing terminal icon.
- Provide hover detail (port for the server, output dir for webpack).
- Click-to-summon the user's iTerm hotkey window via a configured keystroke preference.
- Keep the menu bar visually quieter by removing the now-redundant "Space N" suffix from rows.

**Non-Goals:**
- Launching, restarting, or killing Fleet/webpack processes from projecthub.
- Tracking multiple concurrent Fleet servers as separate first-class entities (the user has indicated they'll handle multiplicity via tabs in the hotkey window).
- A general per-project task framework (e.g. user-defined regex patterns). The Fleet/webpack patterns are hardcoded for v1; the seams should be clean enough that a future change can lift them into config without restructuring.
- Driving iTerm2 directly via AppleScript or its Python API for window summoning.

## Decisions

### Decision: Process introspection via `libproc` rather than shelling to `ps`

Use `proc_listpids`, `proc_pidpath`, and `proc_pidinfo(PROC_PIDARGS2INFO)` / `proc_pidinfo(PROC_PIDVNODEPATHINFO)` to enumerate processes, executable paths, argv, and current working directory. No shell-out, no parser fragility.

**Alternatives considered:**
- Shelling to `ps -eo pid,command,...` — works, but introduces a shell dependency and command-output parsing for a feature that runs every few seconds. Rejected.
- Using `sysctl` `KERN_PROC` directly — equivalent to `libproc` but more verbose and less idiomatic on macOS. Rejected.

### Decision: Scan cadence and lifecycle

Run the process scan on a periodic timer (e.g. every 2–3 seconds) while the menu bar is present. Pause / throttle when the menu bar is not the user's focus is not necessary in v1 — the cost of a `libproc` scan over a few hundred PIDs is negligible. Cancel/restart the timer when the menu opens/closes if simpler given AppKit's `NSMenu` lifecycle; otherwise run it always.

**Rationale:** The cost is low and the responsiveness payoff is real (the user expects the indicator to disappear shortly after they ctrl-C a process). A more elaborate event-driven approach (`kqueue` on PID exits, etc.) is over-engineering for this use case.

### Decision: Webpack ownership via `--output` parent, falling back to cwd

When attributing a webpack process to a project, prefer the parent directory of `--output <path>` if `--output` is present in argv; otherwise use the process cwd. Then match against project paths using **longest-prefix wins**.

**Rationale:** The user runs webpack from the *frontend* repo but writes assets into the *server* repo's `assets/` subdirectory. Their mental model treats the server project as the "owner" of that build because that's where the visible output lives. cwd-only matching would put the indicator on the wrong project.

**Alternatives considered:**
- cwd-only matching — simpler but produces wrong attribution for the user's actual workflow. Rejected.
- Always require `--output` — too strict; webpack is sometimes run without it. Rejected.

### Decision: Port discovery for Fleet server

Try in this order:
1. Parse the server's argv for `--listen <addr>` / `--server_address <addr>` / equivalent and extract the port.
2. If argv parsing yields nothing, query the listening sockets owned by the PID (e.g. `proc_pidinfo` with `PROC_PIDLISTFDS` + `PROC_PIDFDSOCKETINFO`, filtering for TCP listen sockets) and pick the lowest port.
3. If both fail, hover shows a neutral fallback string ("Fleet server running") rather than an error.

**Rationale:** argv is cheap and deterministic; socket inspection is a robust fallback. We avoid trying to read or parse Fleet's config file from disk.

### Decision: Click target separation within the row

Use a custom `NSMenuItem.view` for each project row so the row contains independent click regions: the row body (existing Space-switch behavior) and each indicator (hotkey-window summon). projecthub already uses custom row layout to right-align the terminal icon, so this isn't new surface area.

**Rationale:** A standard `NSMenuItem` has one click target. The user explicitly wants different click behavior for the row vs. the indicator.

### Decision: Hotkey-window summon via posted `CGEvent`, with a configured keystroke preference

Add a new `app-preferences` field — the iTerm hotkey-window keystroke as a `(modifierMask, keyCode)` pair — and post it via `CGEvent` when an indicator is clicked. Mirrors the existing Space-switch pattern.

**Alternatives considered:**
- Driving iTerm2 directly via AppleScript / Python API — iTerm2's hotkey window is a UI mechanic not cleanly exposed as a scriptable verb (you can `activate` iTerm but not toggle the hotkey window in/out reliably). Brittle. Rejected.
- Using a hardcoded keystroke — defeats the user's right to choose their own iTerm hotkey. Rejected.
- A separate "summon" mechanism that doesn't use the user's iTerm hotkey at all (e.g. raise/focus the iTerm window with a known title) — works only if a window already exists; the iTerm hotkey handles the create-if-missing case for free. Rejected.

### Decision: Hardcode Fleet/webpack patterns in v1; design for easy lift later

Implement the detector as a small list of `(label, matchFn(executablePath, argv) -> Bool, ownerDir(argv, cwd) -> URL)` entries hardcoded in the Swift source. Don't expose them via JSON, settings UI, or per-project config in v1.

**Rationale:** The user explicitly said "just Fleet for now." Doing the generic version up front is YAGNI. The detector entries are localized — a future change can lift them into a per-project task list with surgical edits, not a refactor.

## Risks / Trade-offs

- **[Risk] Process attribution is "almost reliable" but not bulletproof.** A user who launches `fleet serve` from `/tmp/scratch` while pointing config at a project directory will see no indicator. → Mitigation: documented behavior; this is the failure mode the user already implicitly accepts. The longest-prefix rule and the `--output` heuristic cover the actual workflow.
- **[Risk] Custom NSMenuItem views have AppKit gotchas (highlight rendering, accessibility).** → Mitigation: existing terminal icon already lives in a custom row layout, so there's a working precedent in the codebase. Reuse it.
- **[Risk] Posting an arbitrary `CGEvent` keystroke requires Accessibility permission, which the app already requests.** No additional permission is needed, but if the user has revoked it, indicator clicks will silently fail at the OS level. → Mitigation: existing Accessibility-missing dialog already handles this for Space-switching; the indicator click reuses the same precondition check.
- **[Risk] Removing the visible Space number is a UX change some users may not expect.** → Mitigation: this is documented as an explicit (non-breaking-data) change in the proposal; Space numbers remain in the Edit Projects window. If we hear pushback, a future toggle in Preferences is cheap.
- **[Trade-off] A 2–3s scan interval means the indicators lag slightly behind reality.** → Mitigation: acceptable for the use case; the user is not making real-time control decisions.

## Migration Plan

No data migration required. The new `app-preferences` field is additive — older `preferences.json` files load with the field unset, which is the well-defined "no keystroke configured" state. The menu bar row redesign is purely visual.

## Open Questions

- **Indicator order.** Right-aligned, but is the order `🎨 🌐 🖥` or `🌐 🎨 🖥`? Either is fine; pick one and be consistent. Defer to implementation taste.
- **Tooltip mechanic.** AppKit tooltips on custom views via `addToolTip(_:owner:userData:)` work fine but require the views to be inside a tracking area; details to confirm during implementation.
- **Fleet listen-flag spelling.** v1 should parse the actual flag(s) Fleet uses. Verify against current Fleet CLI before shipping; fall back to socket inspection when uncertain.
