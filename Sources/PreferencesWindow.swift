import AppKit
import ProjectHubKit
import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var store = PreferencesStore.shared

    var body: some View {
        Form {
            Section {
                Picker(
                    "Terminal:",
                    selection: Binding(
                        get: { store.preferences.terminalApp },
                        set: { store.setTerminalApp($0) }
                    )
                ) {
                    ForEach(TerminalChoice.allCases, id: \.self) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 260)

                if !TerminalLauncher.isAvailable(store.preferences.terminalApp) {
                    Text("\(store.preferences.terminalApp.displayName) is not installed on this system.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            } header: {
                Text("External applications")
                    .font(.headline)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
