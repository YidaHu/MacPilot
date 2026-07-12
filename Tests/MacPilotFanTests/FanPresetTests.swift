import XCTest
@testable import MacPilotFan

final class FanPresetTests: XCTestCase {
    func testPresetMapsIntoEachFansVerifiedRange() {
        let fans = [
            fan(index: 0, minimum: 1_200, maximum: 5_900),
            fan(index: 1, minimum: 2_000, maximum: 5_500)
        ]

        let targets = FanPreset.balanced.targets(for: fans)

        XCTAssertEqual(targets[0]!, 3_785, accuracy: 0.1)
        XCTAssertEqual(targets[1]!, 3_925, accuracy: 0.1)
    }

    func testManualNormalizedPositionIsClamped() {
        let fan = fan(index: 0, minimum: 1_200, maximum: 5_900)
        XCTAssertEqual(FanPreset.manual.targets(for: [fan], manualNormalized: -1)[0], 1_200)
        XCTAssertEqual(FanPreset.manual.targets(for: [fan], manualNormalized: 2)[0], 5_900)
    }

    func testAutomaticPresetDoesNotCreateManualTargets() {
        XCTAssertTrue(FanPreset.automatic.targets(for: [fan(index: 0, minimum: 1_200, maximum: 5_900)]).isEmpty)
    }

    private func fan(index: Int, minimum: Double, maximum: Double) -> FanStatus {
        FanStatus(index: index, actualRPM: minimum, minimumRPM: minimum, maximumRPM: maximum, targetRPM: minimum, controlAvailability: .available)
    }
}
