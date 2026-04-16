import Foundation

/// Returns the project whose `path` is the longest prefix of `cwd` when both
/// are compared on path-component boundaries. A project with no `path` never
/// matches. Returns nil if no project matches.
///
/// Examples:
///   projects: [A:/repo, B:/repo/worktrees/feature]
///   cwd: /repo/worktrees/feature/src       → B
///   cwd: /repo/src                         → A
///   cwd: /other                            → nil
///
/// Boundary-respecting: `/foo/bar` does NOT match `/foo/bart`, because `bart`
/// is not a child of `bar` — they are sibling directories that happen to
/// share a string prefix.
public func matchProject(cwd: String, in projects: [Project]) -> Project? {
    let normalizedCwd = normalizePath(cwd)
    var best: Project?
    var bestLen = -1
    for project in projects {
        guard let rawPath = project.path, !rawPath.isEmpty else { continue }
        let candidate = normalizePath(rawPath)
        guard isDescendantOrEqual(cwd: normalizedCwd, of: candidate) else { continue }
        if candidate.count > bestLen {
            best = project
            bestLen = candidate.count
        }
    }
    return best
}

/// Normalizes a path for prefix comparison: expands `~`, removes any trailing
/// slash (so `/foo/` and `/foo` compare equal), leaves the root `/` alone.
func normalizePath(_ p: String) -> String {
    let expanded = (p as NSString).expandingTildeInPath
    if expanded.count > 1, expanded.hasSuffix("/") {
        return String(expanded.dropLast())
    }
    return expanded
}

/// True iff `cwd` equals `base` or is a descendant on a path-component
/// boundary. Callers should pre-normalize both sides.
func isDescendantOrEqual(cwd: String, of base: String) -> Bool {
    if cwd == base { return true }
    let prefix = base.hasSuffix("/") ? base : base + "/"
    return cwd.hasPrefix(prefix)
}
