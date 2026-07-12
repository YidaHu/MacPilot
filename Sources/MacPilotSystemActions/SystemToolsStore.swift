import Combine
import Foundation
import MacPilotCore

public protocol SystemActionControlling: Sendable {
    func set(_ tool: SystemToolID, enabled: Bool) async -> SystemActionResult
}

extension SystemActionController: SystemActionControlling {}

public protocol PowerAssertionControlling: Sendable {
    func enable(_ kind: PowerAssertionKind, reason: String, duration: TimeInterval?) async throws
    func disable(_ kind: PowerAssertionKind) async
    func disableAll() async
}

extension PowerAssertionController: PowerAssertionControlling {}

@MainActor
public final class SystemToolsStore: ObservableObject {
    @Published public private(set) var errorDescription: String?
    @Published public private(set) var busyTool: SystemToolID?
    @Published private var states: [SystemToolID: SystemToolState] = [:]

    private let actions: any SystemActionControlling
    private let power: any PowerAssertionControlling

    public init(
        actions: any SystemActionControlling = SystemActionController(),
        power: any PowerAssertionControlling = PowerAssertionController()
    ) {
        self.actions = actions
        self.power = power
    }

    public func state(for tool: SystemToolID) -> SystemToolState {
        states[tool] ?? .unknown
    }

    public func toggle(_ tool: SystemToolID) async {
        let enable = state(for: tool) != .enabled
        busyTool = tool
        defer { busyTool = nil }
        do {
            switch tool {
            case .keepAwake:
                try await setPower(.system, enabled: enable, reason: "MacPilot 保持唤醒")
            case .keepDisplayAwake:
                try await setPower(.display, enabled: enable, reason: "MacPilot 保持屏幕亮起")
            case .lowPower, .darkMode, .desktopFiles, .dockVisibility:
                try await setCommand(tool, enabled: enable)
            case .lockScreen, .emptyTrash:
                await trigger(tool)
                return
            case .cleanScreen, .cleanKeyboard, .rocketReminder:
                return
            }
            states[tool] = enable ? .enabled : .disabled
            errorDescription = nil
        } catch {
            errorDescription = error.localizedDescription
        }
    }

    public func trigger(_ tool: SystemToolID) async {
        busyTool = tool
        defer { busyTool = nil }
        let result = await actions.set(tool, enabled: true)
        switch result {
        case .success:
            states[tool] = .disabled
            errorDescription = nil
        case .failed(let message):
            errorDescription = message
        case .handledBySessionController:
            errorDescription = "该功能由安全会话处理"
        }
    }

    public func shutdown() async {
        await power.disableAll()
        states[.keepAwake] = .disabled
        states[.keepDisplayAwake] = .disabled
    }

    private func setPower(_ kind: PowerAssertionKind, enabled: Bool, reason: String) async throws {
        if enabled { try await power.enable(kind, reason: reason, duration: nil) }
        else { await power.disable(kind) }
    }

    private func setCommand(_ tool: SystemToolID, enabled: Bool) async throws {
        switch await actions.set(tool, enabled: enabled) {
        case .success: return
        case .failed(let message): throw SystemToolsStoreError.actionFailed(message)
        case .handledBySessionController: throw SystemToolsStoreError.unsupported
        }
    }
}

private enum SystemToolsStoreError: LocalizedError {
    case actionFailed(String)
    case unsupported

    var errorDescription: String? {
        switch self {
        case .actionFailed(let message): return message
        case .unsupported: return "不支持的系统操作"
        }
    }
}
