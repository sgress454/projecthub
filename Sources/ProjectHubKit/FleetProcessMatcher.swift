import Foundation

/// Per-project process attribution result. A project may have at most one
/// Fleet server and one webpack build attributed to it at a time.
public struct FleetProcessIndicators: Equatable {
    public var server: ServerInfo?
    public var webpack: WebpackInfo?

    public init(server: ServerInfo? = nil, webpack: WebpackInfo? = nil) {
        self.server = server
        self.webpack = webpack
    }

    public var isEmpty: Bool { server == nil && webpack == nil }

    public struct ServerInfo: Equatable {
        public let pid: Int32
        public let port: Int?
        public init(pid: Int32, port: Int?) {
            self.pid = pid
            self.port = port
        }
    }

    public struct WebpackInfo: Equatable {
        public let pid: Int32
        /// Absolute path of the build's effective output directory: the
        /// resolved value of webpack's output flag if present, otherwise the
        /// launching cwd itself.
        public let outputDirectory: String
        /// Whether webpack's output flag was explicitly set. When false,
        /// `outputDirectory` equals the launching cwd and the hover detail
        /// should fall back to the project's own `path`.
        public let hasExplicitOutput: Bool
        /// The launching cwd of the webpack process. Used for project
        /// attribution — webpack belongs to the project where it was launched
        /// (the frontend repo), regardless of where it writes its output.
        public let cwd: String
        public init(pid: Int32, outputDirectory: String, hasExplicitOutput: Bool, cwd: String) {
            self.pid = pid
            self.outputDirectory = outputDirectory
            self.hasExplicitOutput = hasExplicitOutput
            self.cwd = cwd
        }
    }
}

public enum FleetProcessMatcher {
    /// Inspect every snapshot and attribute matched processes to projects via
    /// longest-prefix path matching. Returns a map keyed by project id.
    public static func attribute(
        snapshots: [ProcessSnapshot],
        projects: [Project]
    ) -> [UUID: FleetProcessIndicators] {
        var out: [UUID: FleetProcessIndicators] = [:]
        for snap in snapshots {
            if let server = matchFleetServer(snap) {
                if let project = matchProject(cwd: snap.cwd, in: projects) {
                    var entry = out[project.id] ?? FleetProcessIndicators()
                    entry.server = server
                    out[project.id] = entry
                }
            }
            if let webpack = matchWebpack(snap) {
                if let project = matchProject(cwd: webpack.cwd, in: projects) {
                    var entry = out[project.id] ?? FleetProcessIndicators()
                    entry.webpack = webpack
                    out[project.id] = entry
                }
            }
        }
        return out
    }

    // MARK: - Fleet server

    /// Returns a populated `ServerInfo` if the snapshot looks like a Fleet
    /// server: executable path ends in `/build/fleet` AND argv contains
    /// `serve`. The port is parsed from argv (`--server_address`/`--listen`/
    /// `--port`) when present; callers can fall back to socket inspection
    /// when this returns `nil`.
    public static func matchFleetServer(_ snap: ProcessSnapshot) -> FleetProcessIndicators.ServerInfo? {
        guard isFleetServerExecutable(snap.executablePath) else { return nil }
        guard snap.argv.contains("serve") else { return nil }
        return FleetProcessIndicators.ServerInfo(
            pid: snap.pid,
            port: parseFleetServerPort(argv: snap.argv)
        )
    }

    /// Public so the runtime port-discovery layer can decide whether to
    /// supplement an argv-derived nil with a socket lookup.
    public static func isFleetServerExecutable(_ path: String) -> Bool {
        path.hasSuffix("/build/fleet")
    }

    /// Parse `--server_address host:port` / `--server_address=host:port` /
    /// `--listen host:port` / `--port N` (and equivalent `=`-spelled forms)
    /// into an integer port. Returns nil if no recognized flag is present.
    public static func parseFleetServerPort(argv: [String]) -> Int? {
        let listenKeys: Set<String> = ["--server_address", "--listen", "--address"]
        let portKeys: Set<String> = ["--port", "--server_port"]

        // Build a flattened (key, value) view that tolerates both
        // "--flag value" and "--flag=value" forms.
        var i = 0
        while i < argv.count {
            let tok = argv[i]
            if let (key, val) = splitArg(tok), !val.isEmpty {
                if listenKeys.contains(key), let p = portFromHostPort(val) {
                    return p
                }
                if portKeys.contains(key), let p = Int(val) {
                    return p
                }
            } else if listenKeys.contains(tok), i + 1 < argv.count {
                if let p = portFromHostPort(argv[i + 1]) { return p }
            } else if portKeys.contains(tok), i + 1 < argv.count {
                if let p = Int(argv[i + 1]) { return p }
            }
            i += 1
        }
        return nil
    }

    // MARK: - Webpack

    /// Returns a populated `WebpackInfo` if the snapshot looks like a webpack
    /// build: argv invokes webpack with `--progress` or `--watch`.
    public static func matchWebpack(_ snap: ProcessSnapshot) -> FleetProcessIndicators.WebpackInfo? {
        guard isWebpackInvocation(argv: snap.argv) else { return nil }
        guard snap.argv.contains("--progress") || snap.argv.contains("--watch") else {
            return nil
        }
        let (output, explicit) = effectiveOutputDirectory(argv: snap.argv, cwd: snap.cwd)
        return FleetProcessIndicators.WebpackInfo(
            pid: snap.pid,
            outputDirectory: output,
            hasExplicitOutput: explicit,
            cwd: snap.cwd
        )
    }

    /// True when argv looks like a webpack invocation. We accept either:
    ///   - any token equal to "webpack" (covers `node .../webpack.js webpack ...`,
    ///     `npx webpack`, direct `webpack` binary)
    ///   - a token whose path component ends in `webpack` or `webpack.js`
    public static func isWebpackInvocation(argv: [String]) -> Bool {
        for arg in argv {
            if arg == "webpack" { return true }
            let last = (arg as NSString).lastPathComponent
            if last == "webpack" || last == "webpack.js" { return true }
        }
        return false
    }

    /// Resolve webpack's output-directory flag to an absolute directory,
    /// falling back to `cwd` when no such flag is present. Returns the
    /// resolved path and a flag indicating whether the directory was
    /// explicitly given. Relative paths are resolved against `cwd`.
    ///
    /// Recognized spellings (in webpack 5 + legacy): `--output-path <path>`,
    /// `--output-path=<path>`, `-o <path>`, `--output <path>`,
    /// `--output=<path>`.
    public static func effectiveOutputDirectory(argv: [String], cwd: String) -> (String, Bool) {
        let outputFlags: Set<String> = ["--output-path", "--output", "-o"]
        var i = 0
        while i < argv.count {
            let tok = argv[i]
            if let (key, val) = splitArg(tok), outputFlags.contains(key), !val.isEmpty {
                return (resolveAbsolute(val, relativeTo: cwd), true)
            }
            if outputFlags.contains(tok), i + 1 < argv.count {
                let val = argv[i + 1]
                if !val.isEmpty {
                    return (resolveAbsolute(val, relativeTo: cwd), true)
                }
            }
            i += 1
        }
        return (cwd, false)
    }

    // MARK: - Helpers

    private static func splitArg(_ token: String) -> (String, String)? {
        guard token.hasPrefix("--"), let eq = token.firstIndex(of: "=") else { return nil }
        return (String(token[..<eq]), String(token[token.index(after: eq)...]))
    }

    private static func portFromHostPort(_ value: String) -> Int? {
        // "host:port", ":port", or bare "port".
        if let colon = value.lastIndex(of: ":") {
            return Int(value[value.index(after: colon)...])
        }
        return Int(value)
    }

    private static func resolveAbsolute(_ p: String, relativeTo cwd: String) -> String {
        if p.hasPrefix("/") { return p }
        let expanded = (p as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return expanded }
        return ((cwd as NSString).appendingPathComponent(p) as NSString).standardizingPath
    }
}
