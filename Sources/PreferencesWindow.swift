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

            Section {
                ITermHotkeyShortcutControl(
                    shortcut: store.preferences.iTermHotkeyShortcut,
                    onSet: { store.setITermHotkeyShortcut($0) },
                    onClear: { store.setITermHotkeyShortcut(nil) }
                )
                Text("Pressed when a 🌐 / 🎨 process indicator is clicked, to summon iTerm2's hotkey window. Set the same chord in iTerm2 → Preferences → Keys → Hotkey.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("iTerm hotkey window")
                    .font(.headline)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

/// "Record shortcut" control: while recording, a HID-level CGEventTap
/// captures the next modifier-bearing keystroke and stores it as the iTerm
/// hotkey-window keystroke. The tap intercepts the event before iTerm's
/// already-registered global hotkey can fire, so users can record the same
/// chord that iTerm already owns.
private struct ITermHotkeyShortcutControl: View {
    let shortcut: RecordedShortcut?
    let onSet: (RecordedShortcut) -> Void
    let onClear: () -> Void

    @State private var isRecording = false
    @State private var recorder: HotkeyRecorder?
    @State private var notTrusted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("iTerm hotkey:")
                    .frame(width: 110, alignment: .trailing)

                Button(action: toggleRecording) {
                    Text(buttonLabel)
                        .frame(minWidth: 160)
                }

                if shortcut != nil && !isRecording {
                    Button(action: clear) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear shortcut")
                }

                Spacer()
            }

            if notTrusted {
                Text("Accessibility permission is required to record this shortcut. Open System Settings \u{2192} Privacy & Security \u{2192} Accessibility and turn ProjectHub on.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 118)
            }
        }
    }

    private var buttonLabel: String {
        if isRecording { return "Type a chord\u{2026} (Esc to cancel)" }
        if let s = shortcut { return RecordedShortcutFormatter.displayString(for: s) }
        return "Record shortcut\u{2026}"
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        notTrusted = false
        let rec = HotkeyRecorder(
            onCapture: { captured in
                onSet(captured)
                isRecording = false
                recorder = nil
            },
            onCancel: {
                isRecording = false
                recorder = nil
            }
        )
        switch rec.start() {
        case .started:
            recorder = rec
            isRecording = true
        case .notTrusted:
            notTrusted = true
            SpaceSwitcher.openAccessibilitySettings()
        case .failedToCreateTap:
            notTrusted = true
        }
    }

    private func stopRecording() {
        recorder?.cancel()
        recorder = nil
        isRecording = false
    }

    private func clear() {
        onClear()
    }
}
