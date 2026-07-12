import XCTest
@testable import MacPilotVoice

final class GlobalHotKeyTests: XCTestCase {
    func testResetMakesNextToggleActionStartAgain() {
        var state = HotKeyInteractionState(mode: .toggle)
        XCTAssertEqual(state.handle(.pressed), .startRecording)
        state.reset()
        XCTAssertEqual(state.handle(.pressed), .startRecording)
    }
    func testParsesLegacyOptionSlashShortcut() throws {
        let descriptor = try HotKeyDescriptor.parse("Option+/")
        XCTAssertEqual(descriptor.keyCode, 44)
        XCTAssertNotEqual(descriptor.modifiers, 0)
    }

    func testHoldModeStartsOnPressAndStopsOnRelease() {
        var state = HotKeyInteractionState(mode: .hold)
        XCTAssertEqual(state.handle(.pressed), .startRecording)
        XCTAssertEqual(state.handle(.released), .stopRecording)
    }

    func testToggleModeOnlyActsOnPress() {
        var state = HotKeyInteractionState(mode: .toggle)
        XCTAssertEqual(state.handle(.pressed), .startRecording)
        XCTAssertEqual(state.handle(.released), .none)
        XCTAssertEqual(state.handle(.pressed), .stopRecording)
    }
}
