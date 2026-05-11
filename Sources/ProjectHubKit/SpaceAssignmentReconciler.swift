import Foundation

/// Pure transformations that align project Space assignments with the current
/// macOS Spaces arrangement. Run after every Space-shape change (and once on
/// launch) to keep `project.space` in sync with the position of its cached
/// `spaceID64`.
public enum SpaceAssignmentReconciler {
    /// Returns an updated copy of `projects` with two adjustments:
    /// 1. **Lazy capture:** if a project has no `spaceID64` cached but its
    ///    current `space` corresponds to a real position in `shape`, the id64
    ///    at that position is written into the project.
    /// 2. **Renumber:** if a project's cached `spaceID64` is present in
    ///    `shape` at a different position than its current `space`, `space`
    ///    is updated to the new position. (When the id64 is missing from
    ///    `shape`, the project is "unassigned" — `space` is left at its last
    ///    known value so a later restore is convenient; rendering callers
    ///    detect the unassigned state via `unassignedIDs(...)`).
    ///
    /// When `shape` is empty (CGS unavailable), the input is returned
    /// unchanged so we don't mistakenly clobber assignments on a transient
    /// read failure.
    public static func reconcile(projects: [Project], shape: SpaceShape) -> [Project] {
        guard !shape.isEmpty else { return projects }
        return projects.map { project in
            var copy = project
            if let cached = project.spaceID64 {
                if let newPosition = shape.position(of: cached), newPosition != project.space {
                    copy.space = newPosition
                }
            } else if let id = shape.id(at: project.space) {
                copy.spaceID64 = id
            }
            return copy
        }
    }

    /// Project IDs whose cached `spaceID64` is set but no longer present in
    /// `shape` — i.e. the assigned macOS Space has been removed.
    /// Empty when `shape` is empty (we don't punish projects when CGS is mute).
    public static func unassignedIDs(projects: [Project], shape: SpaceShape) -> Set<UUID> {
        guard !shape.isEmpty else { return [] }
        var result: Set<UUID> = []
        for project in projects {
            guard let cached = project.spaceID64 else { continue }
            if shape.position(of: cached) == nil {
                result.insert(project.id)
            }
        }
        return result
    }
}
