import XCTest
@testable import MacPilotSystemActions
import MacPilotCore

final class SystemActionControllerTests: XCTestCase {
    func testSuccessfulCommandUpdatesToolState() async {
        let runner = FakeRunner(results: [.init(exitCode: 0, standardError: "")])
        let controller = SystemActionController(runner: runner)

        let result = await controller.set(.darkMode, enabled: true)
        let state = await controller.state(for: .darkMode)
        let commands = await runner.commands

        XCTAssertEqual(result, .success)
        XCTAssertEqual(state, .enabled)
        XCTAssertEqual(commands, [.setDarkMode(true)])
    }

    func testFailedCommandDoesNotClaimNewState() async {
        let runner = FakeRunner(results: [.init(exitCode: 1, standardError: "denied")])
        let controller = SystemActionController(runner: runner)

        let result = await controller.set(.lowPower, enabled: true)
        let state = await controller.state(for: .lowPower)

        XCTAssertEqual(result, .failed("denied"))
        XCTAssertEqual(state, .unknown)
    }

    func testSessionToolCannotBecomeArbitraryProcessCommand() async {
        let runner = FakeRunner(results: [])
        let controller = SystemActionController(runner: runner)

        let result = await controller.set(.keepAwake, enabled: true)
        let commands = await runner.commands

        XCTAssertEqual(result, .handledBySessionController)
        XCTAssertEqual(commands, [])
    }

    func testEnablingDesktopFilesToolHidesDesktopFiles() async {
        let runner = FakeRunner(results: [.init(exitCode: 0, standardError: "")])
        let controller = SystemActionController(runner: runner)

        _ = await controller.set(.desktopFiles, enabled: true)
        let commands = await runner.commands

        XCTAssertEqual(commands, [.setDesktopFilesVisible(false)])
    }
}

private actor FakeRunner: ProcessRunning {
    private(set) var commands: [SystemCommand] = []
    private var results: [ProcessResult]

    init(results: [ProcessResult]) {
        self.results = results
    }

    func run(_ command: SystemCommand) async -> ProcessResult {
        commands.append(command)
        return results.removeFirst()
    }
}
