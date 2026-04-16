## 1. Behavior change

- [x] 1.1 Update `StatusCoordinator.dismiss(projectId:)` to clear `red` OR `yellow` to `green` (previously yellow only).
- [x] 1.2 Update `ProjectRowView.configure` so `dismissButton.isHidden = (state.status == .green)` (previously `!= .yellow`).

## 2. Tests

- [x] 2.1 Replace `testDismissRedIsNoOp` with `testDismissRedClearsToGreen` asserting the new behavior.
- [x] 2.2 Keep `testDismissYellowClearsToGreen` and `testDismissGreenIsIdempotent` unchanged — both should still pass.

## 3. Docs

- [x] 3.1 Update README state-machine table: add "red" to the dismiss row.
- [x] 3.2 Update `CHANGELOG.md` with a v0.2.1 entry.

## 4. Validate and archive

- [x] 4.1 `swift test` — all green.
- [x] 4.2 `openspec validate allow-dismiss-red --strict` — clean.
- [ ] 4.3 Smoke: trigger a red while in the project's Space, click ×, confirm cleared to green. **[User verification required]**
- [ ] 4.4 Archive the change. **[User decision]**
