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
        .target(name: "MacPilotSystemActions", dependencies: ["MacPilotCore"]),
        .target(name: "MacPilotCalendar", dependencies: ["MacPilotCore"]),
        .executableTarget(
            name: "MacPilotApp",
            dependencies: ["MacPilotCore", "MacPilotMetrics", "MacPilotSystemActions", "MacPilotCalendar"]
        ),
        .testTarget(name: "MacPilotCoreTests", dependencies: ["MacPilotCore"]),
        .testTarget(name: "MacPilotMetricsTests", dependencies: ["MacPilotMetrics"]),
        .testTarget(name: "MacPilotSystemActionsTests", dependencies: ["MacPilotSystemActions"]),
        .testTarget(name: "MacPilotCalendarTests", dependencies: ["MacPilotCalendar"])
    ]
)
