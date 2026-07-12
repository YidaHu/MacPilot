import Foundation

public enum SystemCommand: Equatable, Sendable {
    case setLowPower(Bool)
    case lockScreen
    case setDarkMode(Bool)
    case setDesktopFilesVisible(Bool)
    case setDockAutoHidden(Bool)
    case emptyTrash
}

public struct ProcessResult: Equatable, Sendable {
    public let exitCode: Int32
    public let standardError: String

    public init(exitCode: Int32, standardError: String) {
        self.exitCode = exitCode
        self.standardError = standardError
    }
}

public protocol ProcessRunning: Sendable {
    func run(_ command: SystemCommand) async -> ProcessResult
}

public actor LiveProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ command: SystemCommand) async -> ProcessResult {
        for invocation in invocations(for: command) {
            let result = run(invocation)
            if result.exitCode != 0 { return result }
        }
        return ProcessResult(exitCode: 0, standardError: "")
    }

    private struct Invocation {
        let executable: String
        let arguments: [String]
    }

    private func invocations(for command: SystemCommand) -> [Invocation] {
        switch command {
        case .setLowPower(let enabled):
            let value = enabled ? "1" : "0"
            let script = "do shell script \"/usr/bin/pmset -b lowpowermode \(value)\" with administrator privileges"
            return [.init(executable: "/usr/bin/osascript", arguments: ["-e", script])]
        case .lockScreen:
            return [.init(
                executable: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession",
                arguments: ["-suspend"]
            )]
        case .setDarkMode(let enabled):
            let value = enabled ? "true" : "false"
            let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(value)"
            return [.init(executable: "/usr/bin/osascript", arguments: ["-e", script])]
        case .setDesktopFilesVisible(let visible):
            return [
                .init(executable: "/usr/bin/defaults", arguments: ["write", "com.apple.finder", "CreateDesktop", "-bool", visible ? "true" : "false"]),
                .init(executable: "/usr/bin/killall", arguments: ["Finder"])
            ]
        case .setDockAutoHidden(let hidden):
            return [
                .init(executable: "/usr/bin/defaults", arguments: ["write", "com.apple.dock", "autohide", "-bool", hidden ? "true" : "false"]),
                .init(executable: "/usr/bin/killall", arguments: ["Dock"])
            ]
        case .emptyTrash:
            return [.init(
                executable: "/usr/bin/osascript",
                arguments: ["-e", "tell application \"Finder\" to empty trash"]
            )]
        }
    }

    private func run(_ invocation: Invocation) -> ProcessResult {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments
        process.standardError = errorPipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            return ProcessResult(
                exitCode: process.terminationStatus,
                standardError: String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        } catch {
            return ProcessResult(exitCode: -1, standardError: error.localizedDescription)
        }
    }
}
