import XCTest
@testable import MacPilotVoice

final class PCMBufferTests: XCTestCase {
    func testConverts48kStereoTo16kMonoWAV() throws {
        let frames = 4_800
        let samples = (0..<frames).flatMap { index -> [Float] in
            let value = Float(index % 100) / 100
            return [value, value]
        }

        let wav = try PCM16WAVEncoder.encode(interleavedSamples: samples, inputSampleRate: 48_000, channels: 2, maximumDuration: 2)

        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(readUInt16(wav, at: 22), 1)
        XCTAssertEqual(readUInt32(wav, at: 24), 16_000)
        XCTAssertEqual(readUInt16(wav, at: 34), 16)
        XCTAssertEqual(readUInt32(wav, at: 40), 3_200)
    }

    func testRejectsEmptyRecording() {
        XCTAssertThrowsError(try PCM16WAVEncoder.encode(interleavedSamples: [], inputSampleRate: 48_000, channels: 1, maximumDuration: 30)) {
            XCTAssertEqual($0 as? AudioCaptureError, .emptyRecording)
        }
    }

    func testRejectsRecordingOverMaximumDuration() {
        XCTAssertThrowsError(try PCM16WAVEncoder.encode(interleavedSamples: Array(repeating: 0, count: 48_001), inputSampleRate: 48_000, channels: 1, maximumDuration: 1)) {
            XCTAssertEqual($0 as? AudioCaptureError, .maximumDurationExceeded)
        }
    }

    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }
}
