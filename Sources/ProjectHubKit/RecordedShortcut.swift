import Foundation

/// User-recordable keystroke (modifier mask + virtual key code) suitable for
/// being replayed via a `CGEvent` keypress. Stored in `preferences.json` and
/// captured by the Preferences modal's "Record shortcut" control.
public struct RecordedShortcut: Equatable {
    public let keyCode: UInt16
    public let modifierFlags: UInt

    public init(keyCode: UInt16, modifierFlags: UInt) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }

    public func toDictionary() -> [String: Any] {
        ["key_code": Int(keyCode), "modifier_flags": Int(modifierFlags)]
    }

    public static func fromDictionary(_ dict: [String: Any]) -> RecordedShortcut? {
        guard let kc = dict["key_code"] as? Int,
              let mf = dict["modifier_flags"] as? Int,
              kc >= 0, mf >= 0
        else { return nil }
        return RecordedShortcut(keyCode: UInt16(kc), modifierFlags: UInt(mf))
    }
}
