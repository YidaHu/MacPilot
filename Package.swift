// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "MacPilot",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "MacPilotApp", targets: ["MacPilotApp"]),
        .executable(name: "MacPilotFanDiagnostic", targets: ["MacPilotFanDiagnostic"]),
        .executable(name: "MacPilotFanHelper", targets: ["MacPilotFanHelperExecutable"]),
        .executable(name: "MacPilotFanRecovery", targets: ["MacPilotFanRecovery"])
    ],
    targets: [
        .target(name: "MacPilotCore"),
        .target(name: "MacPilotMetrics", dependencies: ["MacPilotCore"]),
        .target(name: "MacPilotSystemActions", dependencies: ["MacPilotCore"]),
        .target(name: "MacPilotCalendar", dependencies: ["MacPilotCore"]),
        .target(name: "MacPilotFan"),
        .target(name: "MacPilotVoice"),
        .target(name: "MacPilotFanHelper", dependencies: ["MacPilotFan"]),
        .executableTarget(
            name: "MacPilotFanHelperExecutable",
            dependencies: ["MacPilotFan", "MacPilotFanHelper"]
        ),
        .executableTarget(name: "MacPilotFanDiagnostic", dependencies: ["MacPilotFan"]),
        .executableTarget(name: "MacPilotFanRecovery", dependencies: ["MacPilotFan"]),
        .executableTarget(
            name: "MacPilotApp",
            dependencies: ["MacPilotCore", "MacPilotMetrics", "MacPilotSystemActions", "MacPilotCalendar", "MacPilotFan"]
        ),
        .testTarget(name: "MacPilotCoreTests", dependencies: ["MacPilotCore"]),
        .testTarget(name: "MacPilotMetricsTests", dependencies: ["MacPilotMetrics"]),
        .testTarget(name: "MacPilotSystemActionsTests", dependencies: ["MacPilotSystemActions"]),
        .testTarget(name: "MacPilotCalendarTests", dependencies: ["MacPilotCalendar"]),
        .testTarget(name: "MacPilotFanTests", dependencies: ["MacPilotFan", "MacPilotFanHelper"]),
        .testTarget(name: "MacPilotVoiceTests", dependencies: ["MacPilotVoice"])
    ]
)
