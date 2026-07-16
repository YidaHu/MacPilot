import XCTest
@testable import MacPilotVoice

final class VoiceOperationTrackerTests: XCTestCase {
    func testCancelledOperationIsNoLongerCurrent() {
        var tracker = VoiceOperationTracker()
        let operationID = tracker.begin()

        tracker.cancel()

        XCTAssertFalse(tracker.isCurrent(operationID))
        XCTAssertFalse(tracker.finish(operationID))
    }

    func testStaleOperationCannotFinishNewerOperation() {
        var tracker = VoiceOperationTracker()
        let staleID = tracker.begin()
        let currentID = tracker.begin()

        XCTAssertFalse(tracker.finish(staleID))
        XCTAssertTrue(tracker.isCurrent(currentID))
        XCTAssertTrue(tracker.finish(currentID))
    }
}
