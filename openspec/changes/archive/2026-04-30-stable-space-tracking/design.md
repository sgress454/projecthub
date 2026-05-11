## Context

`SpaceDetector` already calls `CGSCopyManagedDisplaySpaces` to figure out the current Space's positional index. The same response carries each Space's stable `id64` / `ManagedSpaceID` — a 64-bit identifier that survives reordering and is only invalidated when the Space itself is removed. We currently throw that value away after using it once for "which position is current?"

The existing `NSWorkspace.activeSpaceDidChangeNotification` subscription in `AppDelegate` fires not only on Space switches but also on Space-shape changes (add / remove / reorder via Mission Control). That gives us a free trigger for re-reading the displays array.

## Goals / Non-Goals

**Goals:**
- Survive Mission Control reordering of Spaces without silent desynchronization.
- Detect Space removal and update other projects' positional `space` values automatically.
- Surface a clear "this project's Space is gone" state when a cached id64 no longer exists.
- Keep the user-facing model (positional 1–16) unchanged.

**Non-Goals:**
- Multi-display addressing. Today projecthub treats Spaces as a flat 1–16 list; that assumption is preserved. The id64 lookup walks all displays and uses the first match, mirroring `SpaceDetector`'s existing behavior.
- Re-creating a removed Space programmatically. macOS has no public API for this, and the private one is out of scope here.
- Exposing `spaceID64` in the editor UI. It is purely a shadow field.

## Decisions

### Decision: `spaceID64` is an optional shadow field, not a replacement for `space`

The user picks a positional Space (1–16) in the editor; that is the human-facing model and stays the source of truth at edit time. On save, projecthub resolves `space → id64` against the current CGS state and caches the id64 alongside. On load, `space` is the displayed value; on shape-change events, `space` is recomputed from the cached `id64`.

**Rationale:** Keeping the positional value as the user-facing field preserves the "Space N" mental model that maps directly to the macOS keyboard shortcut. The id64 is invisible plumbing.

**Alternatives considered:**
- Storing only `id64` and computing `space` purely on read. Rejected: older binaries reading the file lose the human-meaningful field; the round-trip-unknown-fields contract would still preserve `id64` but the file becomes opaque without a current CGS context.
- Asking the user to pick a Space "by id" via Mission Control inspection. Rejected: nonsense from a UX perspective.

### Decision: Capture `id64` lazily

Existing projects in `projects.json` won't have `space_id64` set on first run after the upgrade. Rather than running a migration on launch, populate it lazily: the first time a Space-shape recompute runs and the project's `space` matches a real position in the current CGS state, write that position's `id64` into the project. Persist on the next save.

**Rationale:** A migration on launch would have to assume the user's Spaces are arranged the way they expect — which is exactly the assumption this change is trying to break. Lazy capture means the first id64 we cache is the one that corresponds to the user's current expectation, not whatever happened to be there at upgrade time.

**Alternatives considered:**
- Migrate immediately on launch. Rejected per the rationale above.
- Require users to re-edit each project to populate the field. Rejected: too much friction for a silent under-the-hood change.

### Decision: Shape-change detection piggybacks on `activeSpaceDidChangeNotification`

`NSWorkspace.activeSpaceDidChangeNotification` fires on Space switches AND on Space-shape changes (creation, removal, reordering). That's our existing subscription, and the extra recompute work it now triggers is cheap (one CGS read + a hash compare).

**Rationale:** Avoids introducing a polling timer or hooking the more obscure CGS connection-notification APIs.

**Alternatives considered:**
- Polling `CGSCopyManagedDisplaySpaces` on a timer. Rejected: wasteful and adds latency.
- `CGSRegisterConnectionNotifyProc` for shape-specific events. Rejected: more private API surface for marginal benefit.

### Decision: Unassigned state surfaces in the menu, not silently

When a project's cached `spaceID64` is not found in the current CGS state, the project's effective `space` is nil. The menu row renders disabled with a "⚠ Space removed — reassign in Edit Projects" hint, and the badge / status logic ignores it for click targeting. The user can re-pick a Space in the editor to rehydrate.

**Rationale:** Silent disappearance would be confusing. Silent reassignment to "some other Space" would be worse.

## Risks / Trade-offs

- **[Risk] CGS internal field name drift.** `id64` and `ManagedSpaceID` are both private dictionary keys we've already been reading. If Apple renames them in a future macOS, both this feature and `SpaceDetector` break together. → Mitigation: belt-and-suspenders read of both keys is already in place; we keep that pattern. If both vanish, we fall back to the positional-only behavior we have today.
- **[Risk] Lazy capture races with a user who reorders Spaces before the first save.** → Mitigation: capture also runs on every shape-change recompute, not just at save time, so the cache populates within one notification of the project being assigned.
- **[Risk] A Space added "between" existing Spaces shifts every higher-numbered project's positional `space` upward, including ones the user didn't intend to disturb.** → This is the *correct* behavior — the positional field has to keep matching the keyboard shortcut. The change in number is honest about what macOS did.
- **[Trade-off] The unassigned state can persist indefinitely if the user ignores the prompt.** Acceptable: the row stays visible and clickable for editing.

## Migration Plan

No file-format migration. `space_id64` is additive and round-trips through the existing extras bucket for v1/v2 readers. Lazy capture handles existing rows on first shape-change recompute after launch.

## Open Questions

- **Display change events.** When the user connects or disconnects a display, the per-display Spaces lists change shape too. Today projecthub flattens them; the recompute logic should handle this gracefully (a project's id64 may move from "display 1, position 4" to "display 2, position 2" or vice versa). The flattened-walk approach should already get this right but is worth a manual check during implementation.
- **Reassignment flow when Space disappears.** Should the editor offer a "next available Space" suggestion, or just the same picker? Defer to UX taste during implementation.
