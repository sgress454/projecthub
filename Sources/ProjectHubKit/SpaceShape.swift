import Foundation

/// Snapshot of the macOS Spaces arrangement: each Space's positional 1-based
/// index paired with its stable CoreGraphics `id64`. Walked in the same order
/// `SpaceDetector.currentSpaceNumber()` walks (display-major, then per-display
/// Space order).
public struct SpaceShape: Equatable {
    public struct Entry: Equatable {
        public let position: Int
        public let id64: UInt64
        public init(position: Int, id64: UInt64) {
            self.position = position
            self.id64 = id64
        }
    }

    public let entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    /// Returns the id64 at the given 1-based position, or nil if no Space is there.
    public func id(at position: Int) -> UInt64? {
        entries.first { $0.position == position }?.id64
    }

    /// Returns the 1-based position of the given id64, or nil if it isn't present.
    public func position(of id64: UInt64) -> Int? {
        entries.first { $0.id64 == id64 }?.position
    }

    public var isEmpty: Bool { entries.isEmpty }

    /// Parse a flattened `SpaceShape` from a CGS-managed-displays array.
    /// The expected shape mirrors `CGSCopyManagedDisplaySpaces`:
    /// `[{ "Spaces": [{ "id64" or "ManagedSpaceID": NSNumber }, ...] }, ...]`.
    /// Spaces missing a usable identifier are skipped but still consume a
    /// positional slot so subsequent positions stay aligned with the OS view.
    public static func parse(displays: [[String: Any]]) -> SpaceShape {
        var entries: [Entry] = []
        var position = 1
        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            for space in spaces {
                if let id = spaceId(from: space) {
                    entries.append(Entry(position: position, id64: id))
                }
                position += 1
            }
        }
        return SpaceShape(entries: entries)
    }

    private static func spaceId(from dict: [String: Any]) -> UInt64? {
        if let n = dict["id64"] as? NSNumber { return n.uint64Value }
        if let n = dict["ManagedSpaceID"] as? NSNumber { return n.uint64Value }
        return nil
    }
}
