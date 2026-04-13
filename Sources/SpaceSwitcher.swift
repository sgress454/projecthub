import AppKit
import ApplicationServices

enum SpaceSwitcher {
    /// Virtual keycodes for the "1"..."9" keys on a US layout.
    /// These match macOS's default "Switch to Desktop N" bindings.
    private static let keyCodes: [Int: CGKeyCode] = [
        1: 0x12, 2: 0x13, 3: 0x14, 4: 0x15,
        5: 0x17, 6: 0x16, 7: 0x1A, 8: 0x1C, 9: 0x19,
    ]

    static func switchTo(space: Int) {
        guard let keyCode = keyCodes[space] else {
            NSLog("ProjectHub: unsupported space number \(space)")
            return
        }
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        down?.flags = .maskControl
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        up?.flags = .maskControl
        up?.post(tap: .cghidEventTap)
    }

    /// Whether macOS has granted Accessibility to this process. If `prompt` is true,
    /// macOS shows its system prompt on the next call that requires it.
    static func hasAccessibility(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts: CFDictionary = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Open System Settings directly to the Accessibility pane.
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
