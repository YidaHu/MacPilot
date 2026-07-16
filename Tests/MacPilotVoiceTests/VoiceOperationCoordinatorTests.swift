import XCTest
@testable import MacPilotVoice

final class VoiceOperationCoordinatorTests: XCTestCase {
    func testVoiceSessionStaysLockedEvenIfUIStageLooksIdleDuringProcessing() {
        var coordinator = VoiceOperationCoordinator()
        guard case let .accepted(startID) = coordinator.begin(.startRecording, during: .idle) else {
            return XCTFail("Expected recording start")
        }
        XCTAssertTrue(coordinator.finish(startID, succeeded: true))
        guard case let .accepted(stopID) = coordinator.begin(.stopRecording, during: .recording) else {
            return XCTFail("Expected recording stop")
        }

        XCTAssertFalse(coordinator.canToggleRecording)
        XCTAssertEqual(
            coordinator.begin(.startRecording, during: .idle),
            .rejected(recording: false)
        )
        XCTAssertTrue(coordinator.shouldPresentError(for: stopID, taskIsCancelled: false))

        XCTAssertTrue(coordinator.finish(stopID, succeeded: true))
        XCTAssertTrue(coordinator.canToggleRecording)
    }

    func testOnlyExplicitCancelUnlocksAProcessingSessionBeforeItFinishes() {
        var coordinator = processingCoordinator()

        XCTAssertFalse(coordinator.canToggleRecording)
        coordinator.cancel()

        XCTAssertTrue(coordinator.canToggleRecording)
        guard case .accepted = coordinator.begin(.startRecording, during: .idle) else {
            return XCTFail("Expected explicit cancel to unlock the session")
        }
    }

    func testProcessingActionDoesNotReplaceCurrentOperation() {
        var coordinator = processingCoordinator()
        let currentID = try! XCTUnwrap(coordinator.activeOperationID)

        let decision = coordinator.begin(.startRecording, during: .transcribing)

        XCTAssertEqual(decision, .rejected(recording: false))
        XCTAssertTrue(coordinator.shouldPresentError(for: currentID, taskIsCancelled: false))
    }

    func testSecondShortcutCannotReplaceStopOperationBeforeStageCallbackArrives() {
        var coordinator = processingCoordinator()
        let currentID = try! XCTUnwrap(coordinator.activeOperationID)

        let decision = coordinator.begin(.stopRecording, during: .recording)

        XCTAssertEqual(decision, .rejected(recording: false))
        XCTAssertTrue(coordinator.shouldPresentError(for: currentID, taskIsCancelled: false))
    }

    func testCancelledOperationCannotPresentAnError() {
        var coordinator = processingCoordinator()
        let operationID = try! XCTUnwrap(coordinator.activeOperationID)

        coordinator.cancel()

        XCTAssertFalse(coordinator.shouldPresentError(for: operationID, taskIsCancelled: false))
        XCTAssertFalse(coordinator.finish(operationID))
    }

    func testCancelledTaskCannotPresentAnErrorWhileStillCurrent() {
        var coordinator = VoiceOperationCoordinator()
        guard case let .accepted(operationID) = coordinator.begin(.startRecording, during: .idle) else {
            return XCTFail("Expected the recording start to be accepted")
        }

        XCTAssertFalse(coordinator.shouldPresentError(for: operationID, taskIsCancelled: true))
    }

    func testRuntimeRebuildIsDeferredUntilProcessingReturnsToIdle() {
        var coordinator = VoiceRuntimeCoordinator()
        guard case let .rebuild(initialGeneration) = coordinator.requestRebuild(during: .idle) else {
            return XCTFail("Expected the initial runtime to be built")
        }

        XCTAssertEqual(coordinator.requestRebuild(during: .structured), .deferred)
        XCTAssertTrue(coordinator.accepts(initialGeneration))
        XCTAssertNil(coordinator.takeDeferredRebuild(during: .outputting))

        let replacementGeneration = coordinator.takeDeferredRebuild(during: .idle)

        XCTAssertNotNil(replacementGeneration)
        XCTAssertFalse(coordinator.accepts(initialGeneration))
        XCTAssertTrue(coordinator.accepts(replacementGeneration!))
        XCTAssertNil(coordinator.takeDeferredRebuild(during: .idle))
    }

    func testRepeatedProcessingRebuildRequestsCollapseIntoOneReplacement() {
        var coordinator = VoiceRuntimeCoordinator()
        _ = coordinator.requestRebuild(during: .idle)

        XCTAssertEqual(coordinator.requestRebuild(during: .transcribing), .deferred)
        XCTAssertEqual(coordinator.requestRebuild(during: .polishing), .deferred)

        XCTAssertNotNil(coordinator.takeDeferredRebuild(during: .idle))
        XCTAssertNil(coordinator.takeDeferredRebuild(during: .idle))
    }

    func testRuntimeRebuildWaitsForRecordingTransitionEvenWhileUIStillLooksIdle() {
        var coordinator = VoiceRuntimeCoordinator()
        guard case let .rebuild(initialGeneration) = coordinator.requestRebuild(during: .idle) else {
            return XCTFail("Expected the initial runtime to be built")
        }

        XCTAssertEqual(
            coordinator.requestRebuild(during: .idle, transitionPending: true),
            .deferred
        )
        XCTAssertTrue(coordinator.accepts(initialGeneration))

        let replacementGeneration = coordinator.takeDeferredRebuild(during: .idle)
        XCTAssertNotNil(replacementGeneration)
        XCTAssertFalse(coordinator.accepts(initialGeneration))
    }

    private func processingCoordinator() -> VoiceOperationCoordinator {
        var coordinator = VoiceOperationCoordinator()
        guard case let .accepted(startID) = coordinator.begin(.startRecording, during: .idle) else {
            return coordinator
        }
        _ = coordinator.finish(startID, succeeded: true)
        _ = coordinator.begin(.stopRecording, during: .recording)
        return coordinator
    }
}
