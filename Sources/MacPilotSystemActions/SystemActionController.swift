import MacPilotCore

public enum SystemActionResult: Equatable, Sendable {
    case success
    case failed(String)
    case handledBySessionController
}

public actor SystemActionController {
    private let runner: any ProcessRunning
    private var states: [SystemToolID: SystemToolState] = [:]

    public init(runner: any ProcessRunning = LiveProcessRunner()) {
        self.runner = runner
    }

    public func state(for tool: SystemToolID) -> SystemToolState {
        states[tool] ?? .unknown
    }

    public func set(_ tool: SystemToolID, enabled: Bool) async -> SystemActionResult {
        guard let command = command(for: tool, enabled: enabled) else {
            return .handledBySessionController
        }
        let result = await runner.run(command)
        guard result.exitCode == 0 else {
            return .failed(result.standardError.isEmpty ? "命令执行失败" : result.standardError)
        }
        states[tool] = enabled ? .enabled : .disabled
        return .success
    }

    private func command(for tool: SystemToolID, enabled: Bool) -> SystemCommand? {
        switch tool {
        case .lowPower: return .setLowPower(enabled)
        case .lockScreen: return .lockScreen
        case .darkMode: return .setDarkMode(enabled)
        case .desktopFiles: return .setDesktopFilesVisible(enabled)
        case .dockVisibility: return .setDockAutoHidden(enabled)
        case .emptyTrash: return .emptyTrash
        case .keepAwake, .keepDisplayAwake, .cleanScreen, .cleanKeyboard, .rocketReminder:
            return nil
        }
    }
}
