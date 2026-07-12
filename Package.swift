// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "MacPilot",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "MacPilotApp", targets: ["MacPilotApp"])
    ],
    targets: [
        .target(name: "MacPilotCore"),
        .target(name: "MacPilotMetrics", dependencies: ["MacPilotCore"]),
        .executableTarget(
            name: "MacPilotApp",
            dependencies: ["MacPilotCore", "MacPilotMetrics"]
        ),
        .testTarget(name: "MacPilotCoreTests", dependencies: ["MacPilotCore"]),
        .testTarget(name: "MacPilotMetricsTests", dependencies: ["MacPilotMetrics"])
    ]
)
