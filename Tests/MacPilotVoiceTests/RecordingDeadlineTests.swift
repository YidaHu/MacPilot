import XCTest
@testable import MacPilotVoice

final class RecordingDeadlineTests: XCTestCase {
    func testDeadlineTriggersOnlyOnceAtTwelveMinutes() {
        var deadline = RecordingDeadline(limit: 720)

        XCTAssertFalse(deadline.consume(elapsed: 719.9))
        XCTAssertTrue(deadline.consume(elapsed: 720))
        XCTAssertFalse(deadline.consume(elapsed: 721))
    }

    func testResetAllowsTheNextRecordingToReachTheDeadline() {
        var deadline = RecordingDeadline(limit: 720)
        XCTAssertTrue(deadline.consume(elapsed: 720))

        deadline.reset()

        XCTAssertTrue(deadline.consume(elapsed: 720))
    }
}
