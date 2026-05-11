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
            // Archived projects are out of band — they carry `space = 0` and
            // `spaceID64 = nil` (the "no positional assignment" shape) and
            // should never be lazy-captured or renumbered.
            if project.archived { return project }
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

    /// Project IDs that should render in the unassigned-active state — visible
    /// in the menu bar as disabled, click opens the editor. Two cases:
    /// 1. `spaceID64` set but missing from `shape` (the project's macOS Space
    ///    was removed).
    /// 2. `space == 0` (the "no positional assignment" sentinel set by
    ///    `Project.archive()` and retained by `Project.restore()`; the user
    ///    needs to pick a Space before the project becomes useful in the bar).
    /// Archived projects are not returned — they have their own section.
    /// Empty when `shape` is empty (we don't punish projects when CGS is mute).
    public static func unassignedIDs(projects: [Project], shape: SpaceShape) -> Set<UUID> {
        guard !shape.isEmpty else { return [] }
        var result: Set<UUID> = []
        for project in projects {
            if project.archived { continue }
            if project.space == 0 {
                result.insert(project.id)
                continue
            }
            guard let cached = project.spaceID64 else { continue }
            if shape.position(of: cached) == nil {
                result.insert(project.id)
            }
        }
        return result
    }
}
