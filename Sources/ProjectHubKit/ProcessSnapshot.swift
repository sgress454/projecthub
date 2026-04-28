import Foundation

/// Point-in-time view of a single running process: PID, executable path, full
/// argv, and current working directory. Produced by `ProcessScanner`.
public struct ProcessSnapshot: Equatable {
    public let pid: Int32
    public let executablePath: String
    public let argv: [String]
    public let cwd: String

    public init(pid: Int32, executablePath: String, argv: [String], cwd: String) {
        self.pid = pid
        self.executablePath = executablePath
        self.argv = argv
        self.cwd = cwd
    }
}
