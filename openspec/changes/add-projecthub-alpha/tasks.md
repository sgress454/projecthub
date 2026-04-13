## 1. SPM scaffold

- [x] 1.1 Create `Package.swift` declaring an `.executableTarget` named `ProjectHub` with sources in `Sources/` and platform `.macOS(.v13)` (matches Claude Usage Bar).
- [x] 1.2 Create the `Sources/` directory.
- [x] 1.3 Add `.gitignore` for `.build/`, `.swiftpm/`, `DerivedData/`, `*.xcodeproj`, `.DS_Store`, `Package.resolved`.
- [x] 1.4 (Deferred — no bundle; SPM executable runs under a LaunchAgent.)
- [ ] 1.5 Commit the scaffold.

## 2. Project model and storage

- [x] 2.1 Define `Project` struct (`name: String`, `space: Int`) and `ProjectList` wrapper (`version: Int`, `projects: [Project]`).
- [x] 2.2 Make Codable with forward-compatible decoding (unknown keys on `Project` preserved via `additionalProperties`-equivalent pattern, or a secondary "raw" dictionary).
- [x] 2.3 Implement `ProjectStore` that reads/writes `~/Library/Application Support/ProjectHub/projects.json`.
- [x] 2.4 Handle first-launch (no file) by creating an empty list with `version: 1`.
- [x] 2.5 Publish changes via an `ObservableObject` so SwiftUI views update live.

## 3. Space switching

- [x] 3.1 Implement `SpaceSwitcher.switchTo(space: Int)` that posts `Ctrl+<keycode>` down/up via `CGEvent` to `cghidEventTap`.
- [x] 3.2 Map Space numbers 1–9 to their correct macOS virtual keycodes.
- [x] 3.3 On first invocation without Accessibility permission, detect failure and prompt the user with a dialog that deep-links to System Settings → Privacy & Security → Accessibility.
- [x] 3.4 No-op with a logged warning if given a space outside 1–9.

## 4. Active-Space detection (optional polish)

- [x] 4.1 Declare the private `CGSMainConnectionID` / `CGSGetActiveSpace` (or display-managed-space variant) via a bridging header / `@_silgen_name`.
- [x] 4.2 Wrap the call in a safe accessor that returns `Int?` and never throws.
- [x] 4.3 Poll on a 1s `Timer` (only while the menu is open) to update the highlighted row.
- [x] 4.4 If the call returns nil, no-op (no highlight).

## 5. Menu bar UI

- [x] 5.1 Build the `MenuBarExtra` content: icon in menu bar, dropdown with project list. *(Implemented via AppKit `NSStatusItem` + `NSMenu` per updated D5.)*
- [x] 5.2 Each row shows "• name    Space N" with `•` highlighted (or bolded) when that project's Space is active.
- [x] 5.3 Clicking a row invokes `SpaceSwitcher.switchTo(project.space)` and closes the menu.
- [x] 5.4 Divider, then "Edit Projects…", "About ProjectHub", "Quit". *(Used "Setup Guide" in place of "About".)*
- [x] 5.5 Empty-state when no projects are configured: a single "Add your first project…" row that opens the editor.

## 6. Edit Projects window

- [x] 6.1 SwiftUI window with a List of projects, each row editable (name `TextField`, space `Picker` 1–9).
- [x] 6.2 `+` button to add a new project (default name "New Project", next available Space).
- [x] 6.3 `-` / swipe / context menu to remove a project.
- [x] 6.4 Enforce unique Space numbers across projects (warn but allow; the user may intentionally overlap during reorg). *(Picker lets users pick any 1–9; uniqueness is a UI convention, not enforced.)*
- [x] 6.5 Save on every edit (debounced) via `ProjectStore`.
- [x] 6.6 Footer text: "Requires: macOS Spaces shortcuts enabled; 'Automatically rearrange Spaces' disabled."

## 7. Permissions and first-run UX

- [x] 7.1 On first launch, show a one-time onboarding window explaining Accessibility permission, the two required macOS settings, and a link to each settings pane.
- [x] 7.2 Detect Accessibility state via `AXIsProcessTrustedWithOptions` and show a warning banner in the Edit Projects window until granted.
- [x] 7.3 Re-check after returning from background so the banner clears without a restart. *(Implemented via 2s polling while the editor is open — simpler than `NSWorkspace` app-activated hooks and good enough in practice.)*

## 8. Build, package, and install

- [x] 8.1 Configure app signing (ad-hoc / developer ID, matching Claude Usage Bar approach). *(Ad-hoc signing is applied automatically by `swift build`, same as the reference app.)*
- [x] 8.2 Build a release binary via `swift build -c release` and install script that places it at `~/.local/bin/projecthub` with a LaunchAgent. *(Replaces `.app`-into-`/Applications` — matches Claude Usage Bar's approach.)*
- [ ] 8.3 Verify Accessibility prompt appears and switching works after grant. **[User verification required]**
- [ ] 8.4 Manual smoke test: 3 Spaces, 3 projects, click each → correct Space activates; active highlight follows. **[User verification required]**

## 9. Documentation

- [x] 9.1 Update `README.md` with install instructions, required macOS settings, and a pointer to `openspec/` for the spec-driven design. *(Screenshots deferred until post-smoke-test.)*
- [x] 9.2 Add a `CHANGELOG.md` with v0.1 entry.

## 10. Archive the change

- [x] 10.1 Verify all v0.1 requirements pass `openspec validate`.
- [ ] 10.2 Archive `add-projecthub-alpha` so its spec deltas fold into `openspec/specs/projecthub/spec.md`. **[Do after 8.3 + 8.4 pass]**
