import XCTest
@testable import ProjectHubKit

final class FleetProcessMatcherTests: XCTestCase {
    private func project(_ name: String, path: String?) -> Project {
        Project(name: name, space: 1, path: path)
    }

    // MARK: - Fleet server matching

    func testFleetServerMatchedByExecutableAndArgv() {
        let snap = ProcessSnapshot(
            pid: 100,
            executablePath: "/Users/x/code/api/build/fleet",
            argv: ["./build/fleet", "serve", "--server_address", ":8080"],
            cwd: "/Users/x/code/api"
        )
        let info = FleetProcessMatcher.matchFleetServer(snap)
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.port, 8080)
    }

    func testNonFleetExecutableNotMatched() {
        let snap = ProcessSnapshot(
            pid: 1, executablePath: "/usr/bin/something",
            argv: ["something", "serve"], cwd: "/tmp"
        )
        XCTAssertNil(FleetProcessMatcher.matchFleetServer(snap))
    }

    func testFleetExecutableWithoutServeNotMatched() {
        let snap = ProcessSnapshot(
            pid: 1, executablePath: "/Users/x/api/build/fleet",
            argv: ["./build/fleet", "version"], cwd: "/Users/x/api"
        )
        XCTAssertNil(FleetProcessMatcher.matchFleetServer(snap))
    }

    // MARK: - Port parsing

    func testPortFromServerAddressEquals() {
        let p = FleetProcessMatcher.parseFleetServerPort(argv: ["--server_address=:9000"])
        XCTAssertEqual(p, 9000)
    }

    func testPortFromListenSpaceSeparated() {
        let p = FleetProcessMatcher.parseFleetServerPort(argv: ["--listen", "0.0.0.0:8443"])
        XCTAssertEqual(p, 8443)
    }

    func testPortFromPortFlag() {
        let p = FleetProcessMatcher.parseFleetServerPort(argv: ["--port", "8080"])
        XCTAssertEqual(p, 8080)
    }

    func testPortFromPortFlagEquals() {
        let p = FleetProcessMatcher.parseFleetServerPort(argv: ["--port=7000"])
        XCTAssertEqual(p, 7000)
    }

    func testNoPortReturnsNil() {
        XCTAssertNil(FleetProcessMatcher.parseFleetServerPort(argv: ["serve"]))
    }

    // MARK: - Webpack matching

    func testWebpackMatchedWithProgress() {
        let snap = ProcessSnapshot(
            pid: 200,
            executablePath: "/usr/local/bin/node",
            argv: ["node", "/path/to/yarn.js", "run", "webpack", "--progress"],
            cwd: "/Users/x/frontend"
        )
        let info = FleetProcessMatcher.matchWebpack(snap)
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.outputDirectory, "/Users/x/frontend")
        XCTAssertFalse(info?.hasExplicitOutput ?? true)
    }

    func testWebpackMatchedWithWatch() {
        let snap = ProcessSnapshot(
            pid: 200,
            executablePath: "/usr/local/bin/node",
            argv: ["node", "webpack", "--watch"],
            cwd: "/Users/x/frontend"
        )
        XCTAssertNotNil(FleetProcessMatcher.matchWebpack(snap))
    }

    func testWebpackWithoutProgressOrWatchNotMatched() {
        let snap = ProcessSnapshot(
            pid: 200, executablePath: "/usr/local/bin/node",
            argv: ["node", "webpack"], cwd: "/Users/x/frontend"
        )
        XCTAssertNil(FleetProcessMatcher.matchWebpack(snap))
    }

    func testWebpackOutputAbsolute() {
        let (out, explicit) = FleetProcessMatcher.effectiveOutputDirectory(
            argv: ["webpack", "--watch", "--output", "/Users/x/server/server/assets"],
            cwd: "/Users/x/frontend"
        )
        XCTAssertEqual(out, "/Users/x/server/server/assets")
        XCTAssertTrue(explicit)
    }

    func testWebpackOutputRelativeResolvedAgainstCwd() {
        let (out, explicit) = FleetProcessMatcher.effectiveOutputDirectory(
            argv: ["webpack", "--watch", "--output=dist/assets"],
            cwd: "/Users/x/frontend"
        )
        XCTAssertEqual(out, "/Users/x/frontend/dist/assets")
        XCTAssertTrue(explicit)
    }

    func testWebpackOutputDefaultsToCwdWhenAbsent() {
        let (out, explicit) = FleetProcessMatcher.effectiveOutputDirectory(
            argv: ["webpack", "--watch"], cwd: "/Users/x/frontend"
        )
        XCTAssertEqual(out, "/Users/x/frontend")
        XCTAssertFalse(explicit)
    }

    func testWebpackOutputPathSpaceSeparated() {
        let (out, explicit) = FleetProcessMatcher.effectiveOutputDirectory(
            argv: ["webpack", "--watch", "--output-path", "/Users/x/server/assets"],
            cwd: "/Users/x/frontend"
        )
        XCTAssertEqual(out, "/Users/x/server/assets")
        XCTAssertTrue(explicit)
    }

    func testWebpackOutputPathEquals() {
        let (out, explicit) = FleetProcessMatcher.effectiveOutputDirectory(
            argv: ["webpack", "--watch", "--output-path=/Users/x/server/assets"],
            cwd: "/Users/x/frontend"
        )
        XCTAssertEqual(out, "/Users/x/server/assets")
        XCTAssertTrue(explicit)
    }

    func testWebpackDashOShortcut() {
        let (out, explicit) = FleetProcessMatcher.effectiveOutputDirectory(
            argv: ["webpack", "--watch", "-o", "/Users/x/server/assets"],
            cwd: "/Users/x/frontend"
        )
        XCTAssertEqual(out, "/Users/x/server/assets")
        XCTAssertTrue(explicit)
    }

    // MARK: - Project attribution

    func testFleetServerAttributedByCwd() {
        let api = project("api", path: "/Users/x/code/api")
        let snap = ProcessSnapshot(
            pid: 1, executablePath: "/Users/x/code/api/build/fleet",
            argv: ["./build/fleet", "serve"], cwd: "/Users/x/code/api"
        )
        let map = FleetProcessMatcher.attribute(snapshots: [snap], projects: [api])
        XCTAssertNotNil(map[api.id]?.server)
        XCTAssertNil(map[api.id]?.webpack)
    }

    func testWebpackAttributedToCwdProjectNotOutputProject() {
        let server = project("server", path: "/Users/x/code/server")
        let frontend = project("frontend", path: "/Users/x/code/frontend")
        let snap = ProcessSnapshot(
            pid: 1, executablePath: "/usr/bin/node",
            argv: ["node", "webpack", "--progress",
                   "--output-path", "/Users/x/code/server/server/assets"],
            cwd: "/Users/x/code/frontend"
        )
        let map = FleetProcessMatcher.attribute(
            snapshots: [snap], projects: [server, frontend]
        )
        XCTAssertNotNil(map[frontend.id]?.webpack)
        XCTAssertNil(map[server.id]?.webpack)
        // Output dir is preserved on the WebpackInfo for tooltip use even
        // though it doesn't drive attribution.
        XCTAssertEqual(map[frontend.id]?.webpack?.outputDirectory, "/Users/x/code/server/server/assets")
        XCTAssertTrue(map[frontend.id]?.webpack?.hasExplicitOutput ?? false)
    }

    func testWebpackWithoutOutputAttributedByCwd() {
        let frontend = project("frontend", path: "/Users/x/code/frontend")
        let snap = ProcessSnapshot(
            pid: 1, executablePath: "/usr/bin/node",
            argv: ["node", "webpack", "--watch"],
            cwd: "/Users/x/code/frontend"
        )
        let map = FleetProcessMatcher.attribute(snapshots: [snap], projects: [frontend])
        XCTAssertNotNil(map[frontend.id]?.webpack)
    }

    func testProcessOutsideAnyProjectIgnored() {
        let api = project("api", path: "/Users/x/code/api")
        let snap = ProcessSnapshot(
            pid: 1, executablePath: "/tmp/scratch/build/fleet",
            argv: ["./build/fleet", "serve"], cwd: "/tmp/scratch"
        )
        let map = FleetProcessMatcher.attribute(snapshots: [snap], projects: [api])
        XCTAssertTrue(map.isEmpty)
    }

    func testLongestPrefixWinsForNestedProjects() {
        let outer = project("monorepo", path: "/Users/x/code/monorepo")
        let inner = project("monorepo-fleet", path: "/Users/x/code/monorepo/fleet")
        let snap = ProcessSnapshot(
            pid: 1, executablePath: "/Users/x/code/monorepo/fleet/build/fleet",
            argv: ["./build/fleet", "serve"], cwd: "/Users/x/code/monorepo/fleet"
        )
        let map = FleetProcessMatcher.attribute(snapshots: [snap], projects: [outer, inner])
        XCTAssertNotNil(map[inner.id]?.server)
        XCTAssertNil(map[outer.id]?.server)
    }

    func testProjectWithoutPathIgnored() {
        let noPath = project("nopath", path: nil)
        let snap = ProcessSnapshot(
            pid: 1, executablePath: "/some/build/fleet",
            argv: ["./build/fleet", "serve"], cwd: "/some"
        )
        let map = FleetProcessMatcher.attribute(snapshots: [snap], projects: [noPath])
        XCTAssertTrue(map.isEmpty)
    }
}
