// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentGuard",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AgentGuard",
            path: "Sources/AgentGuard"
        )
    ]
)
