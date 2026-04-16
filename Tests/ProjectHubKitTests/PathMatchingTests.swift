import XCTest
@testable import ProjectHubKit

final class PathMatchingTests: XCTestCase {
    private func p(_ name: String, path: String?) -> Project {
        Project(name: name, space: 1, path: path)
    }

    func testLongestPrefixWinsForWorktree() {
        let fleet = p("fleet", path: "/Users/x/fleet")
        let worktree = p("fleet-feature", path: "/Users/x/fleet/worktrees/feature")
        let match = matchProject(
            cwd: "/Users/x/fleet/worktrees/feature/src",
            in: [fleet, worktree]
        )
        XCTAssertEqual(match?.name, "fleet-feature")
    }

    func testFallsBackToShorterWhenLongerDoesntApply() {
        let fleet = p("fleet", path: "/Users/x/fleet")
        let worktree = p("fleet-feature", path: "/Users/x/fleet/worktrees/feature")
        let match = matchProject(
            cwd: "/Users/x/fleet/cmd",
            in: [fleet, worktree]
        )
        XCTAssertEqual(match?.name, "fleet")
    }

    func testNoMatchReturnsNil() {
        let fleet = p("fleet", path: "/Users/x/fleet")
        let match = matchProject(cwd: "/Users/x/other", in: [fleet])
        XCTAssertNil(match)
    }

    func testProjectsWithoutPathAreIgnored() {
        let noPath = p("no-path", path: nil)
        let match = matchProject(cwd: "/Users/x/fleet", in: [noPath])
        XCTAssertNil(match)
    }

    func testRespectsPathComponentBoundary() {
        // /foo/bar must NOT match a cwd /foo/bart — "bart" is not a child
        // of "bar", the string prefix match is a trap.
        let bar = p("bar", path: "/foo/bar")
        let match = matchProject(cwd: "/foo/bart/subdir", in: [bar])
        XCTAssertNil(match, "prefix match must respect component boundaries")
    }

    func testExactMatchCountsAsMatch() {
        let proj = p("proj", path: "/Users/x/proj")
        let match = matchProject(cwd: "/Users/x/proj", in: [proj])
        XCTAssertEqual(match?.name, "proj")
    }

    func testTrailingSlashTreatedSame() {
        let proj = p("proj", path: "/Users/x/proj/")
        let match = matchProject(cwd: "/Users/x/proj/src", in: [proj])
        XCTAssertEqual(match?.name, "proj")
    }

    func testTildeExpanded() {
        let home = NSHomeDirectory()
        let proj = p("proj", path: "~/proj")
        let match = matchProject(cwd: "\(home)/proj/src", in: [proj])
        XCTAssertEqual(match?.name, "proj")
    }
}
