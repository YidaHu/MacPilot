// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "MacPilot",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "MacPilotApp", targets: ["MacPilotApp"]),
        .executable(name: "MacPilotFanDiagnostic", targets: ["MacPilotFanDiagnostic"])
    ],
    targets: [
        .target(name: "MacPilotCore"),
        .target(name: "MacPilotMetrics", dependencies: ["MacPilotCore"]),
        .target(name: "MacPilotSystemActions", dependencies: ["MacPilotCore"]),
        .target(name: "MacPilotCalendar", dependencies: ["MacPilotCore"]),
        .target(name: "MacPilotFan"),
        .executableTarget(name: "MacPilotFanDiagnostic", dependencies: ["MacPilotFan"]),
        .executableTarget(
            name: "MacPilotApp",
            dependencies: ["MacPilotCore", "MacPilotMetrics", "MacPilotSystemActions", "MacPilotCalendar"]
        ),
        .testTarget(name: "MacPilotCoreTests", dependencies: ["MacPilotCore"]),
        .testTarget(name: "MacPilotMetricsTests", dependencies: ["MacPilotMetrics"]),
        .testTarget(name: "MacPilotSystemActionsTests", dependencies: ["MacPilotSystemActions"]),
        .testTarget(name: "MacPilotCalendarTests", dependencies: ["MacPilotCalendar"]),
        .testTarget(name: "MacPilotFanTests", dependencies: ["MacPilotFan"])
    ]
)
