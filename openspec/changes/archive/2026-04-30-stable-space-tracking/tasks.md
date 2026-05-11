## 1. Storage and model

- [x] 1.1 Add an optional `spaceID64: UInt64?` field to `Project` (Sources/ProjectHubKit/Project.swift) with `space_id64` JSON key, encode/decode through `toDictionary` / `fromDictionary`, and remove from the extras allow-list.
- [x] 1.2 Confirm round-trip: a v3 file with `space_id64` set loads and re-saves without loss; older files load with `spaceID64 == nil`.

## 2. Space-shape detection

- [x] 2.1 Extend `SpaceDetector` (or add `SpaceShapeReader`) with a function that returns the full `[(position: Int, id64: UInt64)]` flattened across displays, mirroring `currentSpaceNumber`'s walk order.
- [x] 2.2 Add a snapshot type `SpaceShape` (positional → id64 map) plus an equality check.
- [x] 2.3 Unit-test the reader against synthetic CGS dictionary inputs (id64 / ManagedSpaceID key fallback, multi-display flattening).

## 3. Recompute pipeline

- [x] 3.1 Add a `SpaceAssignmentReconciler` that takes a `[Project]` and the current `SpaceShape` and returns the updated `[Project]` (with `space` set to the new position derived from `spaceID64`, or `nil` when the id64 is missing).
- [x] 3.2 Implement lazy id64 capture: when a project has `spaceID64 == nil` but its current `space` corresponds to a real position, write that position's `id64` into the project.
- [x] 3.3 Unit-test reconciliation cases: pure reorder, removal of a project's Space, removal of an unrelated Space (positions shift), insertion of a Space, lazy capture on first run.

## 4. AppDelegate wiring

- [x] 4.1 In the `activeSpaceDidChangeNotification` handler, after refreshing the active Space, read the current `SpaceShape`, run reconciliation against `ProjectStore`, and if anything changed, persist + reload the menu.
- [x] 4.2 On launch, run the same reconciliation once after `ProjectStore` is loaded so the menu reflects current reality before first paint.
- [x] 4.3 Throttle / debounce only if profiling shows a problem — start without it.

## 5. Editor capture path

- [x] 5.1 In `EditProjectsWindow.swift`, when the user changes a project's Space picker, resolve the chosen position to its current `id64` via `SpaceShapeReader` and write both `space` and `spaceID64` together.
- [x] 5.2 If the chosen position has no live id64 (e.g., user picks Space 12 but only 4 Spaces exist), still accept the assignment and leave `spaceID64` nil — lazy capture will set it once the user creates that Space.

## 6. Unassigned-state rendering

- [x] 6.1 In the menu row view, render projects whose effective `space` is nil with a disabled appearance and a "Space removed — reassign in Edit Projects" hint (tooltip and/or trailing affordance).
- [x] 6.2 Make the row click open Edit Projects (focused on that project) instead of attempting a Space switch.
- [x] 6.3 Active-Space highlighting and Space-switching short-circuit to no-op when the project is unassigned.

## 7. Spec updates

- [x] 7.1 `MODIFIED` requirement: project list persistence (adds `space_id64`).
- [x] 7.2 `ADDED` requirement: stable Space identity tracking (id64 cached, recomputed on shape change, lazy capture).
- [x] 7.3 `ADDED` requirement: unassigned-project rendering when cached id64 is missing.
- [x] 7.4 `MODIFIED` requirement: switch to project's Space on click (no-op when unassigned).

## 8. Manual verification

- [X] 8.1 Configure 3 projects on Spaces 1, 2, 3. Reorder via Mission Control. Confirm projecthub's `space` values follow.
- [X] 8.2 Add a new Space "between" projects 2 and 3 in Mission Control. Confirm the project that was on Space 3 is now on Space 4.
- [X] 8.3 Remove a project's Space via Mission Control. Confirm the project renders disabled with the reassign hint and other projects renumber down.
- [X] 8.4 With pre-upgrade `projects.json` loaded, verify `spaceID64` populates after the first shape-change event and is persisted on the next save.
- [X] 8.5 Quit and relaunch; confirm the cached id64s are honored and renumbering still works after a restart.
