import Foundation

public enum AudioCaptureError: Error, Equatable {
    case emptyRecording
    case maximumDurationExceeded
    case invalidFormat
    case microphonePermissionDenied
    case engineUnavailable
}

public enum PCM16WAVEncoder {
    public static func encode(
        interleavedSamples: [Float],
        inputSampleRate: Double,
        channels: Int,
        maximumDuration: TimeInterval
    ) throws -> Data {
        guard inputSampleRate > 0, channels > 0, interleavedSamples.count % channels == 0 else {
            throw AudioCaptureError.invalidFormat
        }
        let frameCount = interleavedSamples.count / channels
        guard frameCount > 0 else { throw AudioCaptureError.emptyRecording }
        let duration = Double(frameCount) / inputSampleRate
        guard duration <= maximumDuration else { throw AudioCaptureError.maximumDurationExceeded }

        var mono = [Float](repeating: 0, count: frameCount)
        for frame in 0..<frameCount {
            var sum: Float = 0
            for channel in 0..<channels { sum += interleavedSamples[frame * channels + channel] }
            mono[frame] = sum / Float(channels)
        }

        let outputRate = 16_000.0
        let outputFrames = max(Int((duration * outputRate).rounded(.down)), 1)
        var pcm = Data(capacity: outputFrames * 2)
        for outputIndex in 0..<outputFrames {
            let inputPosition = Double(outputIndex) * inputSampleRate / outputRate
            let lower = min(Int(inputPosition), mono.count - 1)
            let upper = min(lower + 1, mono.count - 1)
            let fraction = Float(inputPosition - Double(lower))
            let sample = mono[lower] + (mono[upper] - mono[lower]) * fraction
            let clamped = min(max(sample, -1), 1)
            let integer = Int16((clamped * Float(Int16.max)).rounded())
            append(UInt16(bitPattern: integer), to: &pcm)
        }

        var wav = Data()
        wav.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + pcm.count), to: &wav)
        wav.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16), to: &wav)
        append(UInt16(1), to: &wav)
        append(UInt16(1), to: &wav)
        append(UInt32(16_000), to: &wav)
        append(UInt32(32_000), to: &wav)
        append(UInt16(2), to: &wav)
        append(UInt16(16), to: &wav)
        wav.append(contentsOf: Array("data".utf8))
        append(UInt32(pcm.count), to: &wav)
        wav.append(pcm)
        return wav
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
