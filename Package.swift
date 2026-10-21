// swift-tools-version: 6.0
import PackageDescription

#if os(macOS)
let products: [Product] = [
    .executable(name: "MD3Agent", targets: ["MD3Agent"]),
    .library(name: "AgentCore", targets: ["AgentCore"])
]
let coreExclusions: [String] = []
let applicationTargets: [Target] = [.executableTarget(name: "MD3Agent", dependencies: ["AgentCore"])]
#else
// Linux builds exercise portable protocol and storage logic, not the macOS app.
let products: [Product] = [.library(name: "AgentCore", targets: ["AgentCore"])]
let coreExclusions = ["AgentEngine.swift", "KeychainService.swift"]
let applicationTargets: [Target] = []
#endif

let package = Package(
    name: "MD3Agent",
    platforms: [.macOS(.v14)],
    products: products,
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "AgentCore", dependencies: ["CSQLite"], exclude: coreExclusions),
        .testTarget(name: "AgentCoreTests", dependencies: ["AgentCore"])
    ] + applicationTargets,
    swiftLanguageModes: [.v6]
)
