## 1. Storage and model

- [x] 1.1 Add `archived: Bool` (default false) and `archivedAt: Date?` (default nil) properties to `Project`, with `archived` and `archived_at` JSON keys. Encode only when non-default; mirror the existing metadata-field omit-when-empty pattern. Use ISO8601 with timezone offset for `archived_at` serialization.
- [x] 1.2 Add an `archive()` helper on `Project` that returns a copy with `archived = true`, `archivedAt = Date()`, `space = 0` (sentinel for "no positional assignment"), `spaceID64 = nil`, `path = nil`, `claudeEnabled = false`, all other fields intact.
- [x] 1.3 Add a `restore()` helper on `Project` that returns a copy with `archived = false` and `archivedAt = nil`.
- [x] 1.4 Update `ProjectStore` so the menu-bar projection filters out archived projects, but Edit Projects sees the full list partitioned into `active` and `archived` arrays. The `archived` array is sorted by `archivedAt` descending.
- [x] 1.5 Update `SpaceAssignmentReconciler.reconcile` to skip archived projects (defensive — they shouldn't reach reconciliation, but skipping them prevents accidental lazy-capture if they do). Update `unassignedIDs` to include projects with `space == 0` (unifies the "restored, no assignment yet" state with the existing "id64 not in shape" unassigned state).
- [x] 1.6 Unit-test archive round-trip: archive → save → load → assertions on archived flag, archived_at, and that name/links/metadata are intact and space=0/spaceID64=nil/path=nil/claudeEnabled=false.
- [x] 1.7 Unit-test restore round-trip: archive → save → load → restore → save → load → assertions that `archived = false` and `archivedAt = nil`.
- [x] 1.8 Unit-test that pre-archive `projects.json` (no `archived`, no `archived_at`) loads with `archived = false` and `archivedAt = nil` and no errors.
- [x] 1.9 Unit-test that `ProjectStore`'s archived list is sorted by `archivedAt` descending after a load from disk.
- [x] 1.10 Unit-test reconciler invariants: `reconcile` does not modify archived projects; `unassignedIDs` includes a project with `space = 0` even when `spaceID64 = nil` (the post-restore shape).

## 2. Edit Projects window integration

- [ ] 2.1 Add an "Archive" button to each active project row in Edit Projects (next to the existing Delete button).
- [ ] 2.2 Wire the Archive button: call `archive()` on the project, persist via `ProjectStore`, re-render so the row disappears from the active list and appears at the top of the Archived section.
- [ ] 2.3 Add an "Archived" disclosure section below the active list, collapsed by default, with a row count next to the disclosure header (e.g. "Archived (3)").
- [ ] 2.4 Render each archived row with: name, the row's metadata badges (links/PRs/issues if any), and a Restore button. Do not render a Space picker on archived rows.
- [ ] 2.5 Wire the Restore button: call `restore()` on the project, persist, re-render. The restored project appears in the active list as unassigned (no Space) and the Archived section shrinks.
- [ ] 2.6 Confirm the menu bar list excludes archived projects (no row, no badge contribution, no path-prefix matching for Claude hook events).

## 3. Spec updates

- [ ] 3.1 `MODIFIED` requirement: project list persistence — `archived` and `archived_at` fields, round-trip scenarios, pre-archive back-compat scenario.
- [ ] 3.2 `MODIFIED` requirement: menu bar project list — archived projects excluded.
- [ ] 3.3 `MODIFIED` requirement: editing the project list — Archive button, Archived disclosure section ordered by `archived_at` descending, Restore action returning to unassigned-active.

## 4. Manual verification

- [ ] 4.1 Archive an active project from Edit Projects. Confirm it disappears from the menu bar immediately and appears at the top of the Archived section.
- [ ] 4.2 Archive a second project a moment later. Confirm it appears above the first in the Archived section (last-archived-first).
- [ ] 4.3 Quit and relaunch with archived projects in storage. Confirm they reload as archived, the section ordering is preserved, and active projects' Space assignments are unaffected.
- [ ] 4.4 Click Restore on an archived project. Confirm it returns to the active list as unassigned (no Space picker selection), and the Archived section no longer contains it.
- [ ] 4.5 Assign a Space to the restored project via the row's Space picker. Confirm it appears in the menu bar again and the assignment persists across relaunch.
- [ ] 4.6 Load a `projects.json` written by a pre-archive version of the app. Confirm it loads with no archived projects and no errors.
- [ ] 4.7 Archive a project that had Claude monitoring enabled. Confirm a subsequent Claude hook event whose path would have matched the archived project's `path` produces no state change (path is cleared on archive).
