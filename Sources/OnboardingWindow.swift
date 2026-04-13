import SwiftUI

struct OnboardingView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Welcome to ProjectHub")
                .font(.title)
                .bold()

            Text("One-time setup so Space switching works reliably:")
                .foregroundColor(.secondary)

            step(
                number: 1,
                title: "Enable Accessibility permission",
                body: "Required so ProjectHub can send the keyboard shortcut that switches Spaces.",
                buttonTitle: "Open Accessibility Settings",
                action: SpaceSwitcher.openAccessibilitySettings
            )

            step(
                number: 2,
                title: "Enable “Switch to Desktop N” shortcuts",
                body: "In Keyboard → Keyboard Shortcuts → Mission Control, turn on Switch to Desktop 1, 2, 3… These are off by default.",
                buttonTitle: "Open Keyboard Shortcuts",
                action: {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts") {
                        NSWorkspace.shared.open(url)
                    }
                }
            )

            step(
                number: 3,
                title: "Disable “Automatically rearrange Spaces”",
                body: "In Desktop & Dock → Mission Control, turn this OFF. Otherwise Space numbers drift and clicks go to the wrong project.",
                buttonTitle: "Open Desktop & Dock",
                action: {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.expose") {
                        NSWorkspace.shared.open(url)
                    }
                }
            )

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Got it") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520, height: 460)
    }

    @ViewBuilder
    private func step(number: Int, title: String, body: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.title2.bold())
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).bold()
                Text(body)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button(buttonTitle, action: action)
                    .buttonStyle(.link)
                    .padding(.top, 2)
            }
            Spacer()
        }
    }
}
