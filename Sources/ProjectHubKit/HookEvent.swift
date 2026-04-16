import Foundation

/// A single event surfaced by the Claude Code hook into `events.jsonl`.
/// Matches the subset of Claude's hook stdin payload that ProjectHub cares
/// about, plus a `ts` field written by the hook script itself.
public struct HookEvent: Equatable, Codable {
    public var ts: Date
    public var kind: Kind
    public var cwd: String
    public var transcriptPath: String?

    /// Kinds we subscribe to. Other Claude hook events (e.g. `SessionStart`)
    /// are ignored by ProjectHub.
    public enum Kind: String, Codable {
        case stop = "Stop"
        case notification = "Notification"
        case userPromptSubmit = "UserPromptSubmit"
        case preToolUse = "PreToolUse"
        case postToolUse = "PostToolUse"
    }

    public init(ts: Date = Date(), kind: Kind, cwd: String, transcriptPath: String? = nil) {
        self.ts = ts
        self.kind = kind
        self.cwd = cwd
        self.transcriptPath = transcriptPath
    }

    // The hook script writes lines like:
    //   {"ts":"2026-04-15T19:00:00Z","hook_event_name":"Stop","cwd":"/p",
    //    "transcript_path":"/tmp/x.jsonl", ...}
    // We only care about these four fields; the rest is ignored.
    private enum RawKeys: String, CodingKey {
        case ts
        case kind = "hook_event_name"
        case cwd
        case transcriptPath = "transcript_path"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: RawKeys.self)
        // ts: ISO-8601; accept Z or fractional seconds, fall back to current time.
        if let s = try c.decodeIfPresent(String.self, forKey: .ts),
           let parsed = Self.iso8601Parser.date(from: s)
        {
            self.ts = parsed
        } else {
            self.ts = Date()
        }
        self.kind = try c.decode(Kind.self, forKey: .kind)
        self.cwd = try c.decode(String.self, forKey: .cwd)
        self.transcriptPath = try c.decodeIfPresent(String.self, forKey: .transcriptPath)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: RawKeys.self)
        try c.encode(Self.iso8601Formatter.string(from: ts), forKey: .ts)
        try c.encode(kind, forKey: .kind)
        try c.encode(cwd, forKey: .cwd)
        try c.encodeIfPresent(transcriptPath, forKey: .transcriptPath)
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let iso8601Parser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
