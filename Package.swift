// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProjectHub",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "ProjectHubKit",
            path: "Sources/ProjectHubKit"
        ),
        .executableTarget(
            name: "ProjectHub",
            dependencies: ["ProjectHubKit"],
            path: "Sources",
            exclude: ["ProjectHubKit"]
        ),
        .testTarget(
            name: "ProjectHubKitTests",
            dependencies: ["ProjectHubKit"],
            path: "Tests/ProjectHubKitTests"
        ),
    ]
)
