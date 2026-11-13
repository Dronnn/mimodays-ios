// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MimoDaysKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "AppFeature", targets: ["AppFeature"]),
        .library(name: "TestSupport", targets: ["TestSupport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.7"),
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "DesignSystem", resources: [.process("Resources")]),
        .target(name: "Persistence", dependencies: ["Core"]),
        .target(name: "AppFeature", dependencies: ["Core", "DesignSystem"], resources: [.process("Resources")]),
        .target(
            name: "TestSupport",
            dependencies: [
                "Core",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            resources: [.copy("Fixtures")]
        ),
        // Unit tests, one target per module.
        .testTarget(name: "CoreTests", dependencies: ["Core", "TestSupport"]),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
        .testTarget(name: "AppFeatureTests", dependencies: ["AppFeature"]),
        // Integration tests: in-memory SwiftData + temporary file store.
        .testTarget(name: "IntegrationTests", dependencies: ["Core", "Persistence", "TestSupport"]),
        // Screen snapshots: light/dark, iPhone regular/compact, iPad, AX3.
        .testTarget(name: "SnapshotTests", dependencies: ["AppFeature", "DesignSystem", "TestSupport"]),
    ]
)
