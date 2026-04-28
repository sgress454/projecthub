import AppKit
import ProjectHubKit

/// Posts the user-configured iTerm hotkey-window keystroke as a global
/// `CGEvent`, mirroring the pattern used by `SpaceSwitcher` for "Switch to
/// Desktop N". The actual hotkey is owned by iTerm2's preferences; we just
/// replay whatever the user told us to.
enum HotkeyPoster {
    enum PostResult: Equatable {
        case posted
        case unset
        case notTrusted
    }

    @discardableResult
    static func postITermHotkey() -> PostResult {
        guard let shortcut = PreferencesStore.shared.preferences.iTermHotkeyShortcut else {
            return .unset
        }
        guard SpaceSwitcher.hasAccessibility() else {
            return .notTrusted
        }
        post(shortcut: shortcut)
        return .posted
    }

    private static func post(shortcut: RecordedShortcut) {
        let src = CGEventSource(stateID: .hidSystemState)
        let flags = cgFlags(from: shortcut.modifierFlags)

        let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(shortcut.keyCode), keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(shortcut.keyCode), keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
    }

    /// Translate the NSEvent.ModifierFlags raw value (as stored in
    /// `RecordedShortcut.modifierFlags`) into the `CGEventFlags` mask
    /// CGEvent expects.
    private static func cgFlags(from rawNSFlags: UInt) -> CGEventFlags {
        let ns = NSEvent.ModifierFlags(rawValue: rawNSFlags)
        var out: CGEventFlags = []
        if ns.contains(.command)   { out.insert(.maskCommand) }
        if ns.contains(.control)   { out.insert(.maskControl) }
        if ns.contains(.option)    { out.insert(.maskAlternate) }
        if ns.contains(.shift)     { out.insert(.maskShift) }
        if ns.contains(.capsLock)  { out.insert(.maskAlphaShift) }
        if ns.contains(.function)  { out.insert(.maskSecondaryFn) }
        return out
    }
}

/// Render a stored `RecordedShortcut` as a chord string like "⌃⌥⌘T". Used by
/// the Preferences modal's display label.
enum RecordedShortcutFormatter {
    static func displayString(for shortcut: RecordedShortcut) -> String {
        let ns = NSEvent.ModifierFlags(rawValue: shortcut.modifierFlags)
        var s = ""
        if ns.contains(.control) { s += "\u{2303}" } // ⌃
        if ns.contains(.option)  { s += "\u{2325}" } // ⌥
        if ns.contains(.shift)   { s += "\u{21E7}" } // ⇧
        if ns.contains(.command) { s += "\u{2318}" } // ⌘
        s += keyLabel(for: shortcut.keyCode)
        return s
    }

    private static let keyMap: [UInt16: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G",
        0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q",
        0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T", 0x12: "1",
        0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=",
        0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
        0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P", 0x25: "L",
        0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";", 0x2A: "\\", 0x2B: ",",
        0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".", 0x32: "`",
        0x24: "\u{21A9}", // Return
        0x30: "\u{21E5}", // Tab
        0x31: "Space",
        0x33: "\u{232B}", // Delete
        0x35: "Esc",
        0x60: "F5", 0x61: "F6", 0x62: "F7", 0x63: "F3", 0x64: "F8", 0x65: "F9",
        0x67: "F11", 0x69: "F13", 0x6A: "F16", 0x6B: "F14", 0x6D: "F10",
        0x6F: "F12", 0x71: "F15", 0x76: "F4", 0x78: "F2", 0x7A: "F1",
        0x7B: "\u{2190}", 0x7C: "\u{2192}", 0x7D: "\u{2193}", 0x7E: "\u{2191}",
    ]

    private static func keyLabel(for code: UInt16) -> String {
        keyMap[code] ?? String(format: "Key 0x%02X", code)
    }
}
