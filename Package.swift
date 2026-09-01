// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexUsageMenubar",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexUsageCore", targets: ["CodexUsageCore"]),
        .executable(name: "CodexUsageMenubar", targets: ["CodexUsageMenubar"]),
        .executable(name: "codex-usage", targets: ["CodexUsageCLI"])
    ],
    targets: [
        .target(name: "CodexUsageCore"),
        .executableTarget(name: "CodexUsageMenubar", dependencies: ["CodexUsageCore"]),
        .executableTarget(name: "CodexUsageCLI", dependencies: ["CodexUsageCore"]),
        .testTarget(name: "CodexUsageCoreTests", dependencies: ["CodexUsageCore"])
    ]
)
