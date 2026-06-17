## Context

`stable-space-tracking` defines an "unassigned-active" state: a project that exists in the store but has no Space assignment yet, visible in Edit Projects but hidden from the menu bar. Archive piggybacks on that state to express "finished" projects: same hidden-from-menu-bar treatment, plus an `archived` flag that segregates them into their own section of Edit Projects so the active list stays uncluttered.

The original proposal bundled this with auto-closing the project's windows. Window-closing carries enough independent risk — undocumented CGS calls for window-to-Space mapping, AX `AXCloseButton` behavior across native vs Electron apps, timeout tuning — that it's been split out to a future `auto-close-project-windows` change. The archive flow stands alone and is the small, safe shipping unit.

## Goals / Non-Goals

**Goals:**
- Per-row "Archive" entry point in Edit Projects.
- `archived` and `archived_at` fields persist across launches, round-tripping through older binaries via the extras bucket.
- "Archived" disclosure section in Edit Projects, last-archived-first, collapsed by default.
- Restore returns the project to unassigned-active without any new UI — the user reassigns a Space from the row's existing Space picker.

**Non-Goals:**
- Closing the project's windows (deferred to `auto-close-project-windows`).
- Programmatic Space removal.
- Restore-time window reopening or app relaunching.
- Multi-button confirmation dialog (Delete already has its own destructive confirm; Archive is reversible).

## Decisions

### Decision: Archive is metadata-only; Space-related fields are stripped

`archived = true` sets `space = 0` (the "no positional assignment" sentinel — see the next decision), clears `space_id64`, `path`, and `claude_enabled`. Preserved fields: `id`, `name`, `github_issues`, `github_prs`, `links`, `openspec_change`, `summary`. The user retains "what this project was about" without any active monitoring or windowing state.

**Rationale:** Archive is "remember it for later," not "hibernate it." Re-acquiring the Space and path on Restore is cheap and matches the user's mental model. Stripping `claude_enabled` in particular avoids confusing state where archived projects continue to participate in hook routing.

### Decision: `space = 0` is the "no positional assignment" sentinel; unassigned states are unified

`Project.space` is non-optional (`Int`), inherited from stable-space-tracking which models unassigned-by-id64 rather than unassigned-by-space. Rather than widening the data model to `Int?` (which would ripple through the reconciler, EditProjectsWindow, AppDelegate, and StatusCoordinator), `archive()` writes `space = 0`. Position numbers are 1..16 everywhere else in the codebase, so 0 naturally falls below the floor: `SpaceShape.id(at: 0)` returns nil, `nextAvailableSpace()` doesn't enumerate it, and Space-switching comparisons (`project.space == activeSpaceNumber`, where the right side is always ≥1) never match.

A post-Restore project carries `space = 0, spaceID64 = nil, archived = false`. To render this without a parallel "unassigned-restored" state, `SpaceAssignmentReconciler.unassignedIDs` is extended to return any project with `space == 0` in addition to the existing case (`spaceID64` set but missing from `shape`). Both cases produce the same disabled-in-menu-bar, click-opens-editor behavior already defined by stable-space-tracking.

The reconciler also skips archived projects entirely in `reconcile()` — defensive, since active code paths should never pass them in, but it prevents lazy-capture from silently reassigning a freshly-archived project's `spaceID64` to whatever's currently at its (already-cleared) position.

**Rationale:** One sentinel value, one unassigned-rendering path, zero new fields, minimal blast radius. The trade-off is a magic-number-shaped Int, mitigated by `archive()` and the reconciler comments stating the convention explicitly.

**Alternatives considered:**
- Make `space: Int?` optional. Rejected: ripples through every site that reads `project.space`, with no behavioral payoff over the sentinel.
- Add a separate `spaceAssignmentCleared: Bool` field. Rejected: another field to round-trip; mostly redundant with `archived || space == 0`.
- Use `space = -1` or a negative sentinel. Rejected: 0 sits naturally below the 1..16 range and is what `SpaceShape.id(at:)` already treats as "no such position."

### Decision: Add `archived_at` for ordering

`archived_at` is an ISO8601 string set when the user clicks Archive, cleared on Restore.

**Rationale:** The Archived section orders last-archived-first. Relying on JSON-file order is brittle (dictionary iteration order isn't guaranteed across all serialization paths). An explicit timestamp survives any serialization quirks, is human-inspectable in the file, and would also support future "archived this week" framing if we ever want it.

**Alternatives considered:**
- Append-only counter. Rejected: adds shared state, no benefit over a timestamp.
- File order. Rejected: not durable to round-trip; first-archive-first leak would be invisible until a user noticed.

### Decision: No confirmation dialog on Archive

Clicking the Archive button archives the project immediately. There is no "Are you sure?" prompt. If the user archives by mistake, Restore is one click away in the Archived section. Delete (existing, destructive) keeps its current confirm.

**Rationale:** Friction is for destructive operations. Archive is the soft path; making it gated would push users toward Delete. The visual feedback (row disappears from active list, appears at the top of Archived) is the confirmation.

**Alternatives considered:**
- Single-button "Are you sure?" confirm. Rejected as friction for a reversible operation.
- Multi-button Archive/Delete dialog (as in the original close-project design). Rejected: collapsing two distinct actions into one button confuses their semantics (one reversible, one not).

### Decision: Restore returns to unassigned-active; no Space-picker prompt

Restore clears `archived` and `archived_at` only. `space` stays at 0 and `spaceID64` stays nil, carried forward from the archived state. The project re-enters the unassigned-active state (per `stable-space-tracking`, extended above to include `space == 0`): visible in Edit Projects, rendered as a disabled row in the menu bar with a hint that the project needs a Space assignment. The user picks a Space from the Space picker that's already on every active row, which calls `setSpace(id:space:spaceID64:)` and lifts the project out of the unassigned state.

**Rationale:** No new UI for a rare action. The Space picker already lives on the row and already handles the unassigned → assigned transition. Reusing the disabled-row treatment means one mental model for "this project has no Space assigned right now," whether that's because the user just restored it or because macOS removed its Space.

### Decision: Archive lives in Edit Projects, not the menu bar dropdown

Same posture as the existing Delete: heavyweight (or at least deliberate) lifecycle actions live in the editor. The menu bar dropdown stays fast and fully reversible-by-click.

**Rationale:** The user shouldn't be one stray menu-bar click from archiving an active project.

## Risks / Trade-offs

- **[Risk] User intends Archive but clicks Delete (or vice versa).** → Acceptable: they're adjacent in the row, but Delete already has its own destructive confirm. Archive having no confirm and Delete having one creates a learnable asymmetry.
- **[Risk] Archived count grows unboundedly.** → Acceptable for now: the section is collapsed by default, ordered last-archived-first, and there's no menu-bar cost. If it becomes a pain we add bulk-delete or a 30-day auto-purge later.
- **[Trade-off] Archive doesn't close windows.** → Documented. The user closes the windows themselves; the empty Space gets caught by `stable-space-tracking` on the next reconcile. Auto-close ships as a future change layered on this one.
- **[Trade-off] `archived_at` strings without timezone info would sort wrong.** → Mitigation: write ISO8601 with timezone offset (or always UTC). Either is fine as long as the format is consistent.

## Migration Plan

No file-format migration. Both `archived` and `archived_at` are additive and default to false/nil; older binaries round-trip them through the extras bucket. Existing projects start unarchived and are unaffected. Pre-archive `projects.json` files load with `archived = false` and `archived_at = nil`.

## Open Questions

- **Archived section default state.** Collapsed (proposed) vs expanded. Collapsed reduces clutter; expanded surfaces continued existence. Default to collapsed; revisit if the feature feels hidden in practice.
- **Bulk operations on archived rows.** Out of scope for v1; revisit if real users accumulate >20 archived projects.
