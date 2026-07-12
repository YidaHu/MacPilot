import XCTest
@testable import MacPilotFan

final class FanRequestValidatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testRejectsNegativeAndUnknownFanIndices() {
        let validator = makeValidator()
        XCTAssertThrowsError(try validator.validateManual(fanIndex: -1, targetRPM: 2_000, expiresAt: now.addingTimeInterval(3), now: now, lastRequestAt: nil))
        XCTAssertThrowsError(try validator.validateManual(fanIndex: 1, targetRPM: 2_000, expiresAt: now.addingTimeInterval(3), now: now, lastRequestAt: nil))
    }

    func testRejectsRPMOutsideFreshlyDiscoveredRange() {
        let validator = makeValidator()
        XCTAssertThrowsError(try validator.validateManual(fanIndex: 0, targetRPM: 1_199, expiresAt: now.addingTimeInterval(3), now: now, lastRequestAt: nil))
        XCTAssertThrowsError(try validator.validateManual(fanIndex: 0, targetRPM: 5_901, expiresAt: now.addingTimeInterval(3), now: now, lastRequestAt: nil))
        XCTAssertNoThrow(try validator.validateManual(fanIndex: 0, targetRPM: 3_000, expiresAt: now.addingTimeInterval(3), now: now, lastRequestAt: nil))
    }

    func testRejectsNonFiniteRPM() {
        let validator = makeValidator()
        XCTAssertThrowsError(try validator.validateManual(fanIndex: 0, targetRPM: .nan, expiresAt: now.addingTimeInterval(3), now: now, lastRequestAt: nil))
        XCTAssertThrowsError(try validator.validateManual(fanIndex: 0, targetRPM: .infinity, expiresAt: now.addingTimeInterval(3), now: now, lastRequestAt: nil))
    }

    func testRejectsExpiredOrExcessivelyLongLease() {
        let validator = makeValidator()
        XCTAssertThrowsError(try validator.validateManual(fanIndex: 0, targetRPM: 3_000, expiresAt: now, now: now, lastRequestAt: nil))
        XCTAssertThrowsError(try validator.validateManual(fanIndex: 0, targetRPM: 3_000, expiresAt: now.addingTimeInterval(11), now: now, lastRequestAt: nil))
    }

    func testRejectsExcessiveRequestRate() {
        let validator = makeValidator()
        XCTAssertThrowsError(try validator.validateManual(fanIndex: 0, targetRPM: 3_000, expiresAt: now.addingTimeInterval(3), now: now, lastRequestAt: now.addingTimeInterval(-0.05)))
    }

    func testRejectsUnsupportedMode() {
        let validator = makeValidator()
        XCTAssertEqual(try validator.validateMode("automatic"), .automatic)
        XCTAssertEqual(try validator.validateMode("manual"), .manual)
        XCTAssertThrowsError(try validator.validateMode("turbo"))
    }

    private func makeValidator() -> FanRequestValidator {
        FanRequestValidator(ranges: [0: 1_200...5_900], minimumRequestInterval: 0.1, maximumLeaseDuration: 10)
    }
}
