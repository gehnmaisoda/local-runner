// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "LocalRunnerDaemon",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "Core",
            dependencies: ["Yams"],
            path: "Sources/Core"
        ),
        .executableTarget(
            name: "local-runner",
            dependencies: ["Core"],
            path: "Sources/Daemon"
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            path: "Tests/CoreTests"
        ),
    ]
)
