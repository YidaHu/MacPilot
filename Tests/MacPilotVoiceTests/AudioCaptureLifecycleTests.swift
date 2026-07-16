import XCTest
import AVFoundation
@testable import MacPilotVoice

final class AudioCaptureLifecycleTests: XCTestCase {
    func testConcurrentStartIsRejectedUntilCurrentEngineEnds() {
        var lifecycle = AudioCaptureLifecycle()

        XCTAssertEqual(lifecycle.begin(), 1)
        XCTAssertNil(lifecycle.begin())

        XCTAssertTrue(lifecycle.end(1))

        XCTAssertEqual(lifecycle.begin(), 2)
    }

    func testStaleEngineCannotEndOrAppendToNewGeneration() {
        var lifecycle = AudioCaptureLifecycle()
        let first = lifecycle.begin()!
        XCTAssertTrue(lifecycle.end(first))
        let second = lifecycle.begin()!

        XCTAssertFalse(lifecycle.end(first))
        XCTAssertFalse(lifecycle.isCurrent(first))
        XCTAssertTrue(lifecycle.isCurrent(second))
        XCTAssertTrue(lifecycle.isRunning)
    }

    func testBluetoothInputLetsAudioEngineChooseCompatibleTapFormat() throws {
        let bluetoothFormat = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)
        )

        XCTAssertNil(AudioTapFormatPolicy.installationFormat(for: bluetoothFormat))
    }
}
