import AppKit
import ApplicationServices
import ProjectHubKit

enum SpaceSwitcher {
    enum SwitchResult: Equatable {
        case posted
        case shortcutNotBound(space: Int)
        case unsupportedSpace(Int)
    }

    /// Virtual keycodes for the number-row keys on a US layout, mapped to the
    /// Space numbers users configure as "Switch to Desktop N" shortcuts.
    /// macOS only binds 1–9 by default; 10 (`Control+0`), 11 (`Control+-`),
    /// and 12 (`Control+=`) are conventional extensions the user binds in
    /// Keyboard Shortcuts. 13–16 are omitted — no widely-used convention,
    /// and the unbound-shortcut pre-check will explain the missing binding.
    private static let keyCodes: [Int: CGKeyCode] = [
        1: 0x12, 2: 0x13, 3: 0x14, 4: 0x15,
        5: 0x17, 6: 0x16, 7: 0x1A, 8: 0x1C, 9: 0x19,
        10: 0x1D, 11: 0x1B, 12: 0x18,
    ]

    @discardableResult
    static func switchTo(space: Int) -> SwitchResult {
        guard let keyCode = keyCodes[space] else {
            NSLog("ProjectHub: no keycode mapping for space \(space)")
            return .unsupportedSpace(space)
        }
        // Pre-check: if macOS knows the "Switch to Desktop N" hotkey is
        // disabled, bail out instead of silently posting a keypress that
        // will just beep. Unknown (nil) means we couldn't read the prefs —
        // fall through to posting so we don't regress today's behavior.
        if MissionControlShortcuts.isSwitchToDesktopEnabled(space: space) == false {
            return .shortcutNotBound(space: space)
        }
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        down?.flags = .maskControl
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        up?.flags = .maskControl
        up?.post(tap: .cghidEventTap)
        return .posted
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
