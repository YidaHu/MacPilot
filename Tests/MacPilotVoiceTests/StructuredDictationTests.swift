import XCTest
@testable import MacPilotVoice

final class StructuredDictationTests: XCTestCase {
    func testPromptIsNulFreeTrimmedAndBounded() {
        let value = "  keep it concise\0" + String(repeating: "x", count: 3_000) + "  "
        let settings = StructuredDictationSettings(enabled: true, prompt: value)

        XCTAssertFalse(settings.prompt.contains("\0"))
        XCTAssertEqual(settings.prompt.count, 2_000)
        XCTAssertTrue(settings.prompt.hasPrefix("keep it concise"))
    }

    func testEnablingStructuredModeAlsoEnablesPolish() {
        var settings = VoiceProcessingSettings(polishEnabled: false, structuredDictation: .disabled)

        settings.setStructuredEnabled(true)

        XCTAssertTrue(settings.polishEnabled)
        XCTAssertTrue(settings.structuredDictation.enabled)
    }

    func testDisablingStructuredModeKeepsOrdinaryPolishEnabled() {
        var settings = VoiceProcessingSettings(
            polishEnabled: true,
            structuredDictation: .init(enabled: true, prompt: "按主题整理")
        )

        settings.setStructuredEnabled(false)

        XCTAssertTrue(settings.polishEnabled)
        XCTAssertFalse(settings.structuredDictation.enabled)
        XCTAssertEqual(settings.structuredDictation.prompt, "按主题整理")
    }

    func testEmptyPromptUsesDefault() {
        let settings = StructuredDictationSettings(enabled: true, prompt: "   ")
        XCTAssertEqual(settings.prompt, StructuredDictationSettings.defaultPrompt)
    }
}
