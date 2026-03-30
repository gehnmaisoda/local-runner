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
        .target(
            name: "DaemonLib",
            dependencies: ["Core"],
            path: "Sources/DaemonLib"
        ),
        .executableTarget(
            name: "local-runner",
            dependencies: ["DaemonLib"],
            path: "Sources/Daemon"
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            path: "Tests/CoreTests"
        ),
        .testTarget(
            name: "DaemonTests",
            dependencies: ["DaemonLib"],
            path: "Tests/DaemonTests"
        ),
    ]
)
