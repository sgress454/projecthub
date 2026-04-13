// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProjectHub",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ProjectHub",
            path: "Sources"
        )
    ]
)
