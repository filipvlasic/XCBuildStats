// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "XCBuildStats",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "XCBuildStats",
            path: "Sources/XCBuildStats",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "XCBuildStatsTests",
            dependencies: ["XCBuildStats"],
            path: "Tests/XCBuildStatsTests"
        )
    ]
)
