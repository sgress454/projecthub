import Foundation

// MARK: - Private CoreGraphics (Skylight) symbols
//
// These are undocumented symbols resolved at link time against CoreGraphics.
// They have been stable since ~10.7; yabai, AeroSpace, and others rely on them.
// If they ever disappear or change shape, `currentSpaceNumber()` returns nil
// and the rest of the app keeps working (active-Space highlight just vanishes).

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> Unmanaged<CFArray>?

enum SpaceDetector {
    /// Best-effort: returns the currently active Space's index (1-based) within its display,
    /// or nil if it can't be determined (multi-display edge cases, private API drift, etc.).
    static func currentSpaceNumber() -> Int? {
        let cid = CGSMainConnectionID()
        guard let unmanaged = CGSCopyManagedDisplaySpaces(cid) else { return nil }
        guard let displays = unmanaged.takeRetainedValue() as? [[String: Any]] else { return nil }

        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            let currentDict = display["Current Space"] as? [String: Any]
            let currentId = spaceId(from: currentDict)
            guard let currentId else { continue }
            for (index, space) in spaces.enumerated() {
                if spaceId(from: space) == currentId {
                    return index + 1
                }
            }
        }
        return nil
    }

    private static func spaceId(from dict: [String: Any]?) -> UInt64? {
        guard let dict else { return nil }
        if let n = dict["id64"] as? NSNumber { return n.uint64Value }
        if let n = dict["ManagedSpaceID"] as? NSNumber { return n.uint64Value }
        return nil
    }
}
