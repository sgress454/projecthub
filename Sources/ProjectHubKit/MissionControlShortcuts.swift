import Foundation

/// Inspects macOS Keyboard Shortcuts to determine whether a given
/// "Switch to Desktop N" symbolic hotkey is currently enabled.
///
/// macOS stores Mission Control shortcut state in `AppleSymbolicHotKeys`
/// under the `com.apple.symbolichotkeys` preferences domain. Each entry is
/// keyed by a numeric symbolic-hotkey ID — 118 for Switch to Desktop 1,
/// 119 for Switch to Desktop 2, and so on up to 133 for Switch to Desktop 16.
public enum MissionControlShortcuts {
    public static func isSwitchToDesktopEnabled(space: Int) -> Bool? {
        isSwitchToDesktopEnabled(space: space, reader: systemReader)
    }

    static func isSwitchToDesktopEnabled(
        space: Int,
        reader: () -> [String: Any]?
    ) -> Bool? {
        guard let hotkeyId = symbolicHotkeyId(forSpace: space) else { return nil }
        guard let dict = reader() else { return nil }
        let entry = dict[String(hotkeyId)] as? [String: Any]
        return (entry?["enabled"] as? Bool) ?? false
    }

    static func symbolicHotkeyId(forSpace space: Int) -> Int? {
        guard (1 ... 16).contains(space) else { return nil }
        return 117 + space
    }

    private static func systemReader() -> [String: Any]? {
        let value = CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString
        )
        return value as? [String: Any]
    }
}
