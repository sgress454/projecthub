## Context

### The workflow problem

The user runs 3–5 concurrent software projects of varying complexity, each with its own Claude Code session(s), dev/build servers, editor state, and web assets (CI runs, GitHub issues/PRs, Figma, docs). Current state: one iTerm window with many tabs split across projects, one VSCode window per project, one Chrome window with a mix of tabs across projects. Mental context is overfull; the cost is both attention drift ("which project should I be looking at?") and state reload ("what was I doing in project X an hour ago?").

### Problem decomposition

Five distinct sub-problems hide under "workflow chaos":

1. **Attention routing** — which project needs me right now?
2. **Stall detection** — is Claude waiting on me and I don't know?
3. **State reload** — what was I doing in project X?
4. **Progress drift** — is this project moving?
5. **Concurrency cost** — would fewer parallel projects be faster overall?

The user identified #1 and a variant of #2 (ambient state visibility: Claude working? awaiting review? CI running?) as the two sharpest pains, with asset fragmentation being the #1 pain today.

### Strategy explored

Several directions were evaluated:

- **Use OS primitives better** — macOS Spaces, iTerm arrangements, Chrome profiles/tab groups.
- **Raycast/Hammerspoon scripting** — launcher + window-raising automation.
- **Adopt Arc** — browser with first-class per-project Spaces.
- **Build a standalone hub app** — project manifest, switcher, state dashboard.
- **Reduce N** — cap concurrent projects; fix the root cause, not the symptom.

The chosen approach is **macOS Spaces as the asset-organization primitive**, with one Space per project containing that project's iTerm window, VSCode window, and Chrome window. This gets native `Ctrl+N` teleportation, is free, requires no new tools, and keeps Chrome available for frontend QA (no browser switch required).

The remaining gap — Spaces cannot be labeled natively — is what ProjectHub v0.1 solves.

### Why now

Spaces-only is viable for 2–3 projects via wallpaper memorization but does not scale. ProjectHub v0.1 is a small, focused unlock that makes the Spaces workflow actually usable at 3–5 projects. It is also the platform for future state-visibility features without committing to their full design yet.

## Goals / Non-Goals

**Goals (v0.1):**

- Provide a labeled, clickable list of projects in the macOS menu bar.
- Let the user map project names to Space numbers (1–9) and edit the list.
- Clicking a project switches to its Space instantly.
- Persist the project list across launches.
- Surface the currently active Space if possible, degrading gracefully if not.
- Ship as a native macOS app reusing the stack/approach of the existing Claude Usage Bar menu bar app.

**Non-Goals (v0.1) — explicitly deferred:**

- Monitoring Claude Code session state per project.
- Reading `git status`, open PRs, CI runs, or review requests.
- Raising iTerm / VSCode / Chrome windows programmatically.
- Any Claude Code hook integration.
- Arc browser integration.
- Global hotkeys beyond menu bar clicks.
- Auto-detecting projects by scanning the filesystem.
- Multi-monitor Space handling beyond whatever macOS gives us for free.
- Any kind of activity logging, analytics, or telemetry.

## Decisions

### D1. Space switching via synthesized Ctrl+N keystrokes

**Chosen:** Use `CGEvent` to post a `Ctrl+1`…`Ctrl+9` keystroke to the HID event tap.

**Rejected:** Private CoreGraphics APIs such as `CGSManagedDisplaySetCurrentSpace`.

**Why:** The keystroke approach is stable across macOS versions and is what mature tools in this space use. Private Space-switching APIs have broken across macOS releases (as documented by the yabai/AeroSpec communities). The cost is that the user must keep the "Switch to Desktop N" keyboard shortcuts enabled in System Settings and must disable "Automatically rearrange Spaces based on most recent use" (both already done by the user).

**Implication:** The app requires macOS Accessibility permission on first launch; this is also familiar behavior for any window-automation tool.

### D2. Active-Space detection via private API, graceful degradation

**Chosen:** Use `CGSMainConnectionID()` + `CGSGetActiveSpace()` (or equivalent display-managed-space query) to highlight the current project in the menu bar list. If the symbols are unresolvable or return unexpected values on a future macOS, the highlight silently disappears but the core click-to-switch flow still works.

**Why:** Reading the current Space is pure cosmetic polish in v0.1 and should never take down the app. The symbols are widely used by window managers and well-documented in the community.

### D3. Storage format: JSON on disk, schema-versioned

**Chosen:** `~/Library/Application Support/ProjectHub/projects.json` with a top-level `version` field and a `projects` array. Each project has, at minimum, `name` and `space`. Unknown fields are preserved on read/write (forward-compatible).

**Rejected for v0.1:** UserDefaults (harder to inspect and migrate), SQLite (overkill).

**Why:** The schema will grow as v0.2+ adds state-monitoring fields (repo path, GitHub slug, Claude session path, URLs). A plain JSON file is trivial to extend, trivial to inspect, trivial to back up, and trivial to hand-edit during development.

**Forward shape (not implemented in v0.1, documented here for extensibility):**

```json
{
  "version": 1,
  "projects": [
    {
      "name": "claude-usage-bar",
      "space": 1,
      "path": "~/Development/claude-usage-bar",        // v0.3+
      "github": "scott/claude-usage-bar",               // v0.2+
      "claude_session_dir": "~/.claude/projects/...",   // v0.4+
      "urls": []                                         // v0.3+
    }
  ]
}
```

v0.1 writes only `name` and `space`; additional fields are read and round-tripped if present.

### D4. Space number range 1–9

**Chosen:** Support Spaces 1 through 9.

**Why:** macOS `Ctrl+N` shortcuts natively cover 1–9 (single-digit keys only). Supporting 10+ would require chorded or alternative shortcuts and isn't realistic for a human attention budget anyway. If the user ever needs 10+, that's a signal to revisit concurrency rather than extend ProjectHub.

### D5. Tech stack: Swift, AppKit menu bar + SwiftUI editor/onboarding windows

**Chosen:** Native Swift targeting macOS 13+, built with Swift Package Manager (`swift build -c release`, matching Claude Usage Bar). The menu bar surface uses AppKit (`NSStatusItem` + `NSMenu`); the Edit Projects and Onboarding windows use SwiftUI hosted via `NSHostingView` / `NSHostingController`.

**Why:** Claude Usage Bar is pure AppKit and that pattern handles dynamic menus, keyboard equivalents, and the menu bar lifecycle cleanly — reuse it. SwiftUI, however, makes list-editing forms trivial compared to `NSTableView` drudgery, so use it where it pays off. SPM (not an Xcode project) keeps the repo lightweight and installable via a single shell script, again matching the reference.

**Implication:** No `.xcodeproj` in the repo. Build with `swift build`; install via `install.sh`.

### D6. "Edit Projects…" is a separate window, not an inline menu

**Chosen:** A dedicated editor window opened from the menu, containing a list with add/remove/reorder controls and per-row fields for name and Space number.

**Rejected:** Inline editing within the menu bar menu (cramped, fights macOS menu bar UX).

### D7. No global hotkey in v0.1

**Chosen:** Menu bar click only for v0.1.

**Why:** A global hotkey is a feature-creep risk and requires permission UX, conflict handling, and rebinding UI. `Ctrl+N` is already the global shortcut for switching Spaces directly; a ProjectHub hotkey would duplicate native behavior. Revisit if and only if users need "jump to project by name" via a quick search palette (a v0.2+ feature).

### D8. No network in v0.1

**Chosen:** ProjectHub v0.1 makes zero network calls. All state is local.

**Why:** GitHub/CI integration is v0.2+ territory. Keeping v0.1 offline simplifies sandboxing, permissions, privacy posture, and code signing.

## Risks / Trade-offs

- **Accessibility permission friction.** First-launch UX requires granting Accessibility. Mitigation: clear in-app explanation and a link to the exact settings pane.
- **User must keep `Ctrl+N` shortcuts enabled.** If the user or a future macOS update disables them, switching silently fails. Mitigation: detect failure (the menu item stays active and active-Space doesn't change after click) and surface a "Space switching looks broken — check settings" diagnostic in a later version.
- **Private API for active-Space detection can break.** Mitigated by wrapping in a try/optional pattern and degrading to no-highlight on failure. Not a functional regression.
- **Automatically rearrange Spaces can silently invalidate mappings.** If the user re-enables that setting, Space numbers drift. Mitigation: document this in the Edit Projects window ("Requires: 'Automatically rearrange Spaces' must be OFF").
- **Synthesized keystrokes may be swallowed.** If a focused app binds `Ctrl+N` (e.g., Slack), the keystroke hits the app instead of the system. In practice menu bar clicks briefly cede focus, so this should be rare; if it becomes a real issue, switch to a less commonly bound modifier set and expose it as a setting.
- **No backup or sync.** `projects.json` lives in one location per machine. A user with multiple Macs gets two lists. Acceptable for v0.1.

## Future Roadmap (out of scope, captured to inform v0.1 decisions)

Documented here so that v0.1 design choices (storage extensibility, schema, capability naming) don't paint future phases into a corner.

### v0.2 — State visibility, local-only

- Per-project fields: `path` (for `git status`), optional `claude_session_dir` override.
- Background poller reads `git status --porcelain` and `~/.claude/projects/<encoded-path>/*.jsonl` for each project.
- Menu bar list grows: icons/labels for Claude state (idle/working/stalled) and dirty/clean git tree.

### v0.3 — Remote state: PRs, CI, reviews

- Per-project `github` slug field.
- Uses the `gh` CLI (assumed installed, already used by the user) to fetch open PRs, CI run status, review requests.
- Rate-limited polling; shared cache.

### v0.4 — Claude Code hook integration

- Optional Claude Code hook installer that POSTs events to a local ProjectHub socket / file for real-time stall detection (no polling).
- Per-project `Notification` events become push instead of pull.

### v0.5 — Asset raising

- Per-project manifest fields for iTerm window title, VSCode folder path, Chrome window predicate (or Arc Space name if Arc is ever adopted).
- "Switch" action raises all declared windows in addition to switching the Space.

### v0.6+ — Possibly

- Command palette / global hotkey for keyboard-only project switching.
- Menu bar dashboard mode (larger popover) for richer glanceability.
- Export/import of project list.
- iCloud sync for `projects.json`.

These are not commitments — they are the mental map of where ProjectHub goes, and they exist here so that v0.1 decisions (especially D3 storage schema) stay compatible with them.

## References

- `~/Development/claude-usage-bar` — prior menu bar app by the same user; reuse the approach, structure, and lessons.
- macOS Spaces shortcuts: System Settings → Keyboard → Keyboard Shortcuts → Mission Control → "Switch to Desktop N" (must be enabled).
- macOS Spaces behavior: System Settings → Desktop & Dock → Mission Control → "Automatically rearrange Spaces based on most recent use" (must be OFF).
