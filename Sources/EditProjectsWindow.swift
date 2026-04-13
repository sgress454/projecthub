import SwiftUI

struct EditProjectsView: View {
    @ObservedObject private var store = ProjectStore.shared
    @State private var accessibilityGranted: Bool = SpaceSwitcher.hasAccessibility()
    @State private var accessibilityTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !accessibilityGranted {
                accessibilityBanner
            }

            List {
                ForEach(store.projects) { project in
                    ProjectRow(project: project)
                        .padding(.vertical, 2)
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

                Text("Requires: “Switch to Desktop N” enabled · “Automatically rearrange Spaces” disabled")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
            .padding(8)
        }
        .frame(minWidth: 420, minHeight: 340)
        .onAppear(perform: startAccessibilityPolling)
        .onDisappear(perform: stopAccessibilityPolling)
    }

    // MARK: - Accessibility banner

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

    var body: some View {
        HStack(spacing: 10) {
            TextField("Name", text: Binding(
                get: { project.name },
                set: { store.update(id: project.id, name: $0) }
            ))
            .textFieldStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("", selection: Binding(
                get: { project.space },
                set: { store.update(id: project.id, space: $0) }
            )) {
                ForEach(1 ... 9, id: \.self) { n in
                    Text("Space \(n)").tag(n)
                }
            }
            .labelsHidden()
            .frame(width: 110)

            Button {
                store.remove(id: project.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove project")
        }
    }
}
