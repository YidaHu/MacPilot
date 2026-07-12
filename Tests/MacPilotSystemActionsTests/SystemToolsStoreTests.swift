import XCTest
import MacPilotCore
@testable import MacPilotSystemActions

@MainActor
final class SystemToolsStoreTests: XCTestCase {
    func testKeepAwakeToggleCreatesAndReleasesSystemAssertion() async {
        let actions = ActionControllerFake()
        let power = PowerControllerFake()
        let store = SystemToolsStore(actions: actions, power: power)

        await store.toggle(.keepAwake)
        XCTAssertEqual(store.state(for: .keepAwake), .enabled)
        await store.toggle(.keepAwake)
        XCTAssertEqual(store.state(for: .keepAwake), .disabled)
        let operations = await power.operations()
        XCTAssertEqual(operations, [.enable(.system), .disable(.system)])
    }

    func testFailedCommandDoesNotClaimEnabledState() async {
        let actions = ActionControllerFake(result: .failed("denied"))
        let store = SystemToolsStore(actions: actions, power: PowerControllerFake())

        await store.toggle(.darkMode)

        XCTAssertEqual(store.state(for: .darkMode), .unknown)
        XCTAssertEqual(store.errorDescription, "denied")
    }

    func testOneShotActionDoesNotRemainEnabled() async {
        let actions = ActionControllerFake()
        let store = SystemToolsStore(actions: actions, power: PowerControllerFake())

        await store.trigger(.lockScreen)
        let calls = await actions.calls()

        XCTAssertEqual(store.state(for: .lockScreen), .disabled)
        XCTAssertEqual(calls, [.init(tool: .lockScreen, enabled: true)])
    }
}

private struct ActionCall: Equatable {
    let tool: SystemToolID
    let enabled: Bool
}

private actor ActionControllerFake: SystemActionControlling {
    private let result: SystemActionResult
    private var recorded: [ActionCall] = []

    init(result: SystemActionResult = .success) { self.result = result }
    func set(_ tool: SystemToolID, enabled: Bool) async -> SystemActionResult {
        recorded.append(.init(tool: tool, enabled: enabled))
        return result
    }
    func calls() -> [ActionCall] { recorded }
}

private enum PowerOperation: Equatable {
    case enable(PowerAssertionKind)
    case disable(PowerAssertionKind)
}

private actor PowerControllerFake: PowerAssertionControlling {
    private var recorded: [PowerOperation] = []
    func enable(_ kind: PowerAssertionKind, reason: String, duration: TimeInterval?) async throws { recorded.append(.enable(kind)) }
    func disable(_ kind: PowerAssertionKind) async { recorded.append(.disable(kind)) }
    func disableAll() async {}
    func operations() -> [PowerOperation] { recorded }
}
