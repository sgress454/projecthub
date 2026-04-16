import Foundation

/// Scans a project path for OpenSpec changes and auto-detects
/// which change is associated with the project.
public enum OpenSpecDetector {
    /// Returns the single active change name if exactly one non-archive
    /// subdirectory exists in `<path>/openspec/changes/`, nil otherwise.
    public static func detectChange(at projectPath: String) -> String? {
        let changesDir = (projectPath as NSString).appendingPathComponent("openspec/changes")
        let resolvedDir: String
        // Resolve symlinks.
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: changesDir, isDirectory: &isDir) {
            resolvedDir = (changesDir as NSString).resolvingSymlinksInPath
        } else {
            return nil
        }
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: resolvedDir) else {
            return nil
        }
        let candidates = entries.filter { $0 != "archive" && !$0.hasPrefix(".") }
        return candidates.count == 1 ? candidates[0] : nil
    }

    /// Lists all active (non-archive) change names at the given project path.
    public static func listChanges(at projectPath: String) -> [String] {
        let changesDir = (projectPath as NSString).appendingPathComponent("openspec/changes")
        let resolvedDir = (changesDir as NSString).resolvingSymlinksInPath
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: resolvedDir) else {
            return []
        }
        return entries
            .filter { $0 != "archive" && !$0.hasPrefix(".") }
            .sorted()
    }
}
