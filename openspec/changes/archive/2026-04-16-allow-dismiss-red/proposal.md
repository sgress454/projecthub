## Why

`add-project-status` shipped dismiss as yellow-only, with the reasoning that red means "Claude is genuinely waiting" and clearing it would hide a real block. Real use surfaced a gap: red can fire while the user is *already* in the target project's Space (a `Notification` / Stop+QUESTION at the moment they're reading). The active-Space downgrade only fires on *change*, not on steady-state presence — so red persists until the user switches away and back, which is the exact friction ProjectHub is supposed to eliminate.

## What Changes

- **MODIFIED** dismiss semantics: clears `yellow` OR `red` to `green`. Green is still a no-op.
- **MODIFIED** per-row dismiss control visibility: shown on red OR yellow rows (not only yellow).
- Tests updated; spec scenarios under the dismiss requirement updated.

## Capabilities

### Modified Capabilities

- `projecthub`: dismiss now covers red, not just yellow.

## Impact

- Behavior change only. No schema, hook, CLI, or data-model changes.
- The user still cannot accidentally dismiss a genuine block: the × button is explicit and per-row; it doesn't fire on the row click that switches Spaces.
