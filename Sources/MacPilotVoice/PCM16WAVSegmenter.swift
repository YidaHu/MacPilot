import Foundation

public enum PCM16WAVSegmenter {
    public static func split(_ wavData: Data, maximumDuration: TimeInterval) throws -> [RecordedAudio] {
        guard maximumDuration.isFinite, maximumDuration > 0,
              wavData.count >= 12,
              ascii(wavData, range: 0..<4) == "RIFF",
              ascii(wavData, range: 8..<12) == "WAVE" else {
            throw AudioCaptureError.invalidFormat
        }

        var format: (sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16)?
        var pcmRange: Range<Int>?
        var offset = 12
        while offset + 8 <= wavData.count {
            let chunkID = ascii(wavData, range: offset..<(offset + 4))
            let chunkSize = Int(readUInt32(wavData, at: offset + 4))
            let payloadStart = offset + 8
            let payloadEnd = payloadStart + chunkSize
            guard chunkSize >= 0, payloadEnd <= wavData.count else {
                throw AudioCaptureError.invalidFormat
            }

            if chunkID == "fmt " {
                guard chunkSize >= 16, readUInt16(wavData, at: payloadStart) == 1 else {
                    throw AudioCaptureError.invalidFormat
                }
                format = (
                    sampleRate: readUInt32(wavData, at: payloadStart + 4),
                    channels: readUInt16(wavData, at: payloadStart + 2),
                    bitsPerSample: readUInt16(wavData, at: payloadStart + 14)
                )
            } else if chunkID == "data" {
                pcmRange = payloadStart..<payloadEnd
            }

            offset = payloadEnd + (chunkSize % 2)
        }

        guard let format, let pcmRange,
              format.sampleRate > 0,
              format.channels == 1,
              format.bitsPerSample == 16,
              !pcmRange.isEmpty,
              pcmRange.count.isMultiple(of: 2) else {
            throw AudioCaptureError.invalidFormat
        }

        let bytesPerSecond = Int(format.sampleRate) * 2
        var maximumBytes = Int((Double(bytesPerSecond) * maximumDuration).rounded(.down))
        maximumBytes -= maximumBytes % 2
        guard maximumBytes > 0 else { throw AudioCaptureError.invalidFormat }

        let duration = Double(pcmRange.count) / Double(bytesPerSecond)
        guard pcmRange.count > maximumBytes else {
            return [RecordedAudio(wavData: wavData, duration: duration)]
        }

        let pcmData = wavData.subdata(in: pcmRange)
        var segments: [RecordedAudio] = []
        var start = 0
        while start < pcmData.count {
            let end = min(start + maximumBytes, pcmData.count)
            let segmentPCM = pcmData.subdata(in: start..<end)
            segments.append(RecordedAudio(
                wavData: makeWAV(pcmData: segmentPCM, sampleRate: format.sampleRate),
                duration: Double(segmentPCM.count) / Double(bytesPerSecond)
            ))
            start = end
        }
        return segments
    }

    private static func makeWAV(pcmData: Data, sampleRate: UInt32) -> Data {
        var wav = Data()
        wav.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + pcmData.count), to: &wav)
        wav.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16), to: &wav)
        append(UInt16(1), to: &wav)
        append(UInt16(1), to: &wav)
        append(sampleRate, to: &wav)
        append(sampleRate * 2, to: &wav)
        append(UInt16(2), to: &wav)
        append(UInt16(16), to: &wav)
        wav.append(contentsOf: Array("data".utf8))
        append(UInt32(pcmData.count), to: &wav)
        wav.append(pcmData)
        return wav
    }

    private static func ascii(_ data: Data, range: Range<Int>) -> String? {
        guard range.lowerBound >= 0, range.upperBound <= data.count else { return nil }
        return String(data: data.subdata(in: range), encoding: .ascii)
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8(value >> 8))
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8(value >> 24))
    }
}
