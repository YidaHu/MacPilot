import XCTest
@testable import MacPilotVoice

final class WAVSegmenterTests: XCTestCase {
    func testRecordingBelowLimitStaysAsOneSegment() throws {
        let wav = try makeWAV(seconds: 27)

        let segments = try PCM16WAVSegmenter.split(wav, maximumDuration: 28)

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].wavData, wav)
        XCTAssertEqual(segments[0].duration, 27, accuracy: 0.001)
    }

    func testRecordingAtLimitStaysAsOneSegment() throws {
        let wav = try makeWAV(seconds: 28)

        let segments = try PCM16WAVSegmenter.split(wav, maximumDuration: 28)

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].duration, 28, accuracy: 0.001)
    }

    func testSixtySecondsSplitsIntoTwoFullSegmentsAndRemainder() throws {
        let wav = try makeWAV(seconds: 60)

        let segments = try PCM16WAVSegmenter.split(wav, maximumDuration: 28)

        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0].duration, 28, accuracy: 0.001)
        XCTAssertEqual(segments[1].duration, 28, accuracy: 0.001)
        XCTAssertEqual(segments[2].duration, 4, accuracy: 0.001)
        XCTAssertEqual(segments.reduce(0) { $0 + Int(readUInt32($1.wavData, at: 40)) }, 60 * 16_000 * 2)
        for segment in segments {
            XCTAssertEqual(String(data: segment.wavData.prefix(4), encoding: .ascii), "RIFF")
            XCTAssertEqual(String(data: segment.wavData.subdata(in: 8..<12), encoding: .ascii), "WAVE")
            XCTAssertEqual(readUInt16(segment.wavData, at: 22), 1)
            XCTAssertEqual(readUInt32(segment.wavData, at: 24), 16_000)
            XCTAssertEqual(readUInt16(segment.wavData, at: 34), 16)
        }
    }

    func testRejectsUnsupportedWAVData() {
        XCTAssertThrowsError(try PCM16WAVSegmenter.split(Data("RIFF-invalid".utf8), maximumDuration: 28)) {
            XCTAssertEqual($0 as? AudioCaptureError, .invalidFormat)
        }
    }

    private func makeWAV(seconds: Int) throws -> Data {
        let pcm = Data(repeating: 0x2a, count: seconds * 16_000 * 2)
        var wav = Data("RIFF".utf8)
        append(UInt32(36 + pcm.count), to: &wav)
        wav.append(Data("WAVEfmt ".utf8))
        append(UInt32(16), to: &wav)
        append(UInt16(1), to: &wav)
        append(UInt16(1), to: &wav)
        append(UInt32(16_000), to: &wav)
        append(UInt32(32_000), to: &wav)
        append(UInt16(2), to: &wav)
        append(UInt16(16), to: &wav)
        wav.append(Data("data".utf8))
        append(UInt32(pcm.count), to: &wav)
        wav.append(pcm)
        return wav
    }

    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }

    private func append(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8(value >> 8))
    }

    private func append(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8(value >> 24))
    }
}
