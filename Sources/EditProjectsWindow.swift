import AppKit
import ProjectHubKit
import SwiftUI

struct EditProjectsView: View {
    @ObservedObject private var store = ProjectStore.shared
    @State private var accessibilityGranted: Bool = SpaceSwitcher.hasAccessibility()
    @State private var accessibilityTimer: Timer?

    @State private var hookState: HookInstaller.State = .notInstalled
    @State private var claudeCLIAvailable: Bool = false
    @State private var showPreviewSheet: Bool = false
    @State private var previewBefore: String = ""
    @State private var previewAfter: String = ""
    @State private var installErrorMessage: String?

    // Session-local ordering: the order of IDs to display in the active
    // section of the editor. Seeded on open from the stored order sorted
    // ascending by Space, then left alone for the rest of the session so
    // rows don't jump while the user edits. New projects added during the
    // session append to the end. Archived projects use their own intrinsic
    // order (last-archived-first) and aren't part of this array.
    @State private var displayOrder: [UUID] = []

    @State private var archivedSectionExpanded: Bool = false

    private let installer = HookInstaller()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !accessibilityGranted {
                accessibilityBanner
            }
            claudeStatusSection

            if hookState.installed && !hookState.matches {
                handEditedBanner
            }
            if store.settings.claudeHookInstalled && !claudeCLIAvailable {
                claudeCLIWarningBanner
            }

            List {
                ForEach(orderedProjects(), id: \.id) { project in
                    ProjectRow(project: project)
                        .padding(.vertical, 2)
                }

                if !store.archivedProjects.isEmpty {
                    DisclosureGroup(isExpanded: $archivedSectionExpanded) {
                        ForEach(store.archivedProjects, id: \.id) { project in
                            ArchivedProjectRow(project: project)
                                .padding(.vertical, 2)
                        }
                    } label: {
                        Text("Archived (\(store.archivedProjects.count))")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(.inset)

            Divider()

            HStack(spacing: 8) {
                Button {
                    store.add(space: store.nextAvailableSpace())
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add project")

                Spacer()

                Button("Preferences\u{2026}") {
                    (NSApp.delegate as? AppDelegate)?.openPreferences()
                }
                .controlSize(.small)

                Text("Requires: “Switch to Desktop N” enabled · “Automatically rearrange Spaces” disabled")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
            .padding(8)
        }
        .frame(minWidth: 520, minHeight: 400)
        .onAppear {
            seedDisplayOrder()
            startAccessibilityPolling()
            refreshHookState()
            refreshClaudeAvailability()
        }
        .onChange(of: store.activeProjects.map(\.id)) { _ in
            // Watching the active-set IDs (not store.projects) so archive/
            // restore — which leave the underlying array unchanged but flip
            // the `archived` flag — also triggers a sync.
            syncDisplayOrder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .editProjectsWindowWillShow)) { _ in
            seedDisplayOrder()
        }
        .onDisappear(perform: stopAccessibilityPolling)
        .sheet(isPresented: $showPreviewSheet) {
            HookPreviewSheet(
                before: previewBefore,
                after: previewAfter,
                onConfirm: {
                    showPreviewSheet = false
                    performInstall()
                },
                onCancel: { showPreviewSheet = false }
            )
        }
        .alert(
            "Couldn't update Claude settings",
            isPresented: Binding(
                get: { installErrorMessage != nil },
                set: { if !$0 { installErrorMessage = nil } }
            ),
            actions: { Button("OK") { installErrorMessage = nil } },
            message: { Text(installErrorMessage ?? "") }
        )
    }

    // MARK: - Claude status section

    private var claudeStatusSection: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: store.settings.claudeHookInstalled ? "checkmark.seal.fill" : "questionmark.circle")
                .foregroundColor(store.settings.claudeHookInstalled ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude status monitoring").bold()
                Text(
                    store.settings.claudeHookInstalled
                        ? "Claude Code events flow into ProjectHub. Per-project settings below."
                        : "Install the Claude Code hook so ProjectHub can see permission requests and completions."
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
            Spacer()
            Toggle(
                "",
                isOn: Binding(
                    get: { store.settings.claudeHookInstalled },
                    set: { newValue in
                        if newValue {
                            let preview = installer.previewInstall()
                            previewBefore = preview.before
                            previewAfter = preview.after
                            showPreviewSheet = true
                        } else {
                            performUninstall()
                        }
                    }
                )
            )
            .labelsHidden()
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Banners

    private var accessibilityBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility permission not granted").bold()
                Text("Space switching won't work until ProjectHub is enabled in System Settings → Privacy & Security → Accessibility.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Open Settings") { SpaceSwitcher.openAccessibilitySettings() }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
    }

    private var handEditedBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "pencil.circle.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude hook is out of sync").bold()
                Text("ProjectHub's hook is installed but doesn't match the current version — either because ~/.claude/settings.json was hand-edited, or because a newer ProjectHub build added hook events that aren't registered yet. Re-install to sync.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Re-install") {
                let preview = installer.previewInstall()
                previewBefore = preview.before
                previewAfter = preview.after
                showPreviewSheet = true
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
    }

    private var claudeCLIWarningBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("`claude` CLI not found on PATH").bold()
                Text("Classification will default to RED for every Stop event. Install the Claude CLI or disable Claude status.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: - Install flow

    private func performInstall() {
        do {
            try installer.install()
            store.setClaudeHookInstalled(true)
            // Flush immediately — `install.sh` kills the app on reinstall,
            // which used to race with the 0.3 s debounced save.
            store.flushPendingSave()
            refreshHookState()
            refreshClaudeAvailability()
        } catch {
            installErrorMessage = "Install failed: \(error.localizedDescription)"
        }
    }

    private func performUninstall() {
        do {
            try installer.uninstall()
            store.setClaudeHookInstalled(false)
            store.flushPendingSave()
            refreshHookState()
        } catch {
            installErrorMessage = "Uninstall failed: \(error.localizedDescription)"
        }
    }

    private func refreshHookState() {
        hookState = installer.currentState()
        // The file is the source of truth (it's what actually runs when
        // Claude fires a hook). Reconcile the cached flag in both directions
        // — e.g. if a prior toggle was lost to a kill-before-flush, we'd
        // otherwise show an unchecked box while the hook is still live.
        if store.settings.claudeHookInstalled != hookState.installed {
            store.setClaudeHookInstalled(hookState.installed)
            store.flushPendingSave()
        }
    }

    private func refreshClaudeAvailability() {
        // Force a fresh lookup (checks known install paths, falls back to
        // the user's shell) rather than trusting a cached miss from early
        // startup — the user may have just installed `claude`.
        ClaudeCLI.invalidateCache()
        claudeCLIAvailable = ClaudeCLI.resolve() != nil
    }

    // MARK: - Display order

    private func seedDisplayOrder() {
        // Sort active projects by Space ascending, with stable fallback on
        // stored index so ties don't shuffle randomly. Archived projects
        // are excluded — they live in their own section, sorted by
        // archivedAt descending.
        let stored = store.activeProjects
        let indexed = stored.enumerated().map { ($0.offset, $0.element) }
        displayOrder = indexed
            .sorted { lhs, rhs in
                if lhs.1.space != rhs.1.space { return lhs.1.space < rhs.1.space }
                return lhs.0 < rhs.0
            }
            .map { $0.1.id }
    }

    private func orderedProjects() -> [Project] {
        let active = store.activeProjects
        let byId = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
        var result: [Project] = []
        var seen = Set<UUID>()
        for id in displayOrder {
            if let project = byId[id] {
                result.append(project)
                seen.insert(id)
            }
        }
        // Any project added (or restored) during the session that's not
        // yet in displayOrder appends to the end. `syncDisplayOrder` keeps
        // the state array in step after the store publishes.
        for project in active where !seen.contains(project.id) {
            result.append(project)
        }
        return result
    }

    private func syncDisplayOrder() {
        let activeIds = Set(store.activeProjects.map { $0.id })
        // Drop removed-or-archived projects; keep known ordering for survivors.
        var updated = displayOrder.filter { activeIds.contains($0) }
        let known = Set(updated)
        for project in store.activeProjects where !known.contains(project.id) {
            updated.append(project.id)
        }
        if updated != displayOrder {
            displayOrder = updated
        }
    }

    // MARK: - Accessibility polling

    private func startAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            let granted = SpaceSwitcher.hasAccessibility()
            if granted != accessibilityGranted {
                accessibilityGranted = granted
            }
        }
    }

    private func stopAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
    }
}

private struct ProjectRow: View {
    let project: Project
    @ObservedObject private var store = ProjectStore.shared
    @State private var showMetadata = false

    var body: some View {
        HStack(spacing: 10) {
            TextField("Name", text: Binding(
                get: { project.name },
                set: { store.update(id: project.id, name: $0) }
            ))
            .textFieldStyle(.plain)
            .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)

            Picker("", selection: Binding(
                get: { project.space },
                set: { newSpace in
                    // Capture the current id64 at this position when one
                    // exists; otherwise leave nil and let lazy capture in
                    // the reconciler fill it in once the user creates that
                    // Space in macOS.
                    let id64 = SpaceDetector.currentShape().id(at: newSpace)
                    store.setSpace(id: project.id, space: newSpace, spaceID64: id64)
                }
            )) {
                ForEach(1 ... 16, id: \.self) { n in
                    Text("Space \(n)").tag(n)
                }
            }
            .labelsHidden()
            .frame(width: 110)

            PathPickerControl(project: project)

            Button {
                showMetadata = true
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help("Edit project metadata (issues, PRs, links)")

            Toggle(
                "",
                isOn: Binding(
                    get: { project.claudeEnabled },
                    set: { store.setClaudeEnabled(id: project.id, enabled: $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled((project.path ?? "").isEmpty)
            .help(
                (project.path ?? "").isEmpty
                    ? "Set a path first to enable Claude monitoring for this project."
                    : "Toggle Claude state monitoring for this project."
            )

            Button {
                store.archive(id: project.id)
            } label: {
                Image(systemName: "archivebox")
            }
            .buttonStyle(.borderless)
            .help("Archive project (sets it aside; restorable from the Archived section)")

            Button {
                store.remove(id: project.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove project")
        }
        .sheet(isPresented: $showMetadata) {
            MetadataEditView(projectId: project.id)
        }
    }
}

private struct ArchivedProjectRow: View {
    let project: Project
    @ObservedObject private var store = ProjectStore.shared
    @State private var showMetadata = false

    var body: some View {
        HStack(spacing: 10) {
            Text(project.name)
                .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                .foregroundColor(.secondary)

            if let archivedAt = project.archivedAt {
                Text(Self.relativeFormatter.localizedString(for: archivedAt, relativeTo: Date()))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .help("Archived \(archivedAt.formatted(date: .abbreviated, time: .shortened))")
            }

            Button {
                showMetadata = true
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help("View metadata (read-only browse while archived)")

            Button {
                store.restore(id: project.id)
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help("Restore to active list (you'll pick a Space to reassign)")
        }
        .sheet(isPresented: $showMetadata) {
            MetadataEditView(projectId: project.id)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

/// A small "Path: …" control that opens an NSOpenPanel when clicked. Shows
/// the last component of the path (or "Set path…") as the button label.
private struct PathPickerControl: View {
    let project: Project
    @ObservedObject private var store = ProjectStore.shared

    var body: some View {
        HStack(spacing: 4) {
            Button(action: pickDirectory) {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                    Text(displayLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(width: 120)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(action: clearPath) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Clear path")
            .opacity(project.path != nil ? 1 : 0)
            .disabled(project.path == nil)
        }
    }

    private var displayLabel: String {
        guard let path = project.path, !path.isEmpty else { return "Set path…" }
        return (path as NSString).lastPathComponent
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Project Folder"
        if let path = project.path {
            panel.directoryURL = URL(fileURLWithPath: path)
        }
        if panel.runModal() == .OK, let url = panel.url {
            store.setPath(id: project.id, path: url.path)
        }
    }

    private func clearPath() {
        store.setPath(id: project.id, path: nil)
    }
}

// MARK: - Preview sheet

private struct HookPreviewSheet: View {
    let before: String
    let after: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Confirm Claude hook install")
                .font(.headline)
            Text("ProjectHub will write these changes to ~/.claude/settings.json. Existing hooks of your own are preserved. You can uninstall at any time.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Before").font(.caption).bold()
                    ScrollView {
                        Text(before.isEmpty ? "(empty)" : before)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("After").font(.caption).bold()
                    ScrollView {
                        Text(after)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                }
            }
            .frame(minHeight: 260)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Install hook", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 640, minHeight: 360)
    }
}
