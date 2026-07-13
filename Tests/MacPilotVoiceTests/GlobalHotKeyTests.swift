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

    func testParsesShortcutWithoutModifiers() throws {
        let descriptor = try HotKeyDescriptor.parse("R")

        XCTAssertEqual(descriptor, HotKeyDescriptor(keyCode: 15, modifiers: 0))
        XCTAssertEqual(descriptor.storageValue, "R")
        XCTAssertFalse(descriptor.hasModifiers)
    }

    func testCombinationRoundTripsInCanonicalModifierOrder() throws {
        let descriptor = try HotKeyDescriptor.parse("Shift+Command+Space")

        XCTAssertEqual(descriptor.storageValue, "Command+Shift+Space")
        XCTAssertEqual(try HotKeyDescriptor.parse(descriptor.storageValue), descriptor)
        XCTAssertTrue(descriptor.hasModifiers)
    }

    func testFormatsShortcutForDisplay() throws {
        XCTAssertEqual(
            try HotKeyDescriptor.parse("Command+Option+Control+Shift+Space").displayValue,
            "⌘ ⌥ ⌃ ⇧ Space"
        )
    }

    func testParsesNavigationAndFunctionKeys() throws {
        XCTAssertEqual(try HotKeyDescriptor.parse("Left").keyCode, 123)
        XCTAssertEqual(try HotKeyDescriptor.parse("F12").keyCode, 111)
    }

    func testInvalidStoredShortcutResolvesToDefault() {
        XCTAssertEqual(HotKeyDescriptor.resolve("broken"), .defaultVoice)
        XCTAssertEqual(HotKeyDescriptor.resolve(nil), .defaultVoice)
        XCTAssertEqual(HotKeyDescriptor.defaultVoice.storageValue, "Option+/")
    }

    func testBooleanModifierInitializerUsesCarbonModifiers() {
        let descriptor = HotKeyDescriptor(
            keyCode: 15,
            command: true,
            option: false,
            control: true,
            shift: false
        )

        XCTAssertEqual(descriptor.storageValue, "Command+Control+R")
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
