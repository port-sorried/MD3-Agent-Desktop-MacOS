// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MD3Agent",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MD3Agent", targets: ["MD3Agent"]),
        .library(name: "AgentCore", targets: ["AgentCore"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "AgentCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "MD3Agent", dependencies: ["AgentCore"]),
        .testTarget(name: "AgentCoreTests", dependencies: ["AgentCore"])
    ],
    swiftLanguageModes: [.v6]
)
