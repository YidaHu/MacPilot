import AVFoundation
import Foundation

public final class AVAudioCapture: @unchecked Sendable, AudioCapturing {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private let maximumDuration: TimeInterval
    private let onLevel: @Sendable (Float) -> Void
    private var samples: [Float] = []
    private var sampleRate: Double = 0
    private var channels = 0
    private var running = false

    public init(maximumDuration: TimeInterval = 30, onLevel: @escaping @Sendable (Float) -> Void = { _ in }) {
        self.maximumDuration = maximumDuration
        self.onLevel = onLevel
    }

    public func start() async throws {
        guard await requestMicrophoneAccess() else { throw AudioCaptureError.microphonePermissionDenied }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioCaptureError.invalidFormat }

        lock.withLock {
            samples.removeAll(keepingCapacity: true)
            sampleRate = format.sampleRate
            channels = Int(format.channelCount)
            running = true
        }
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            self?.consume(buffer)
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            lock.withLock { running = false }
            throw AudioCaptureError.engineUnavailable
        }
    }

    public func stop() async throws -> RecordedAudio {
        let capture = stopAndTakeSamples()
        let wav = try PCM16WAVEncoder.encode(
            interleavedSamples: capture.samples,
            inputSampleRate: capture.sampleRate,
            channels: capture.channels,
            maximumDuration: maximumDuration
        )
        let duration = Double(capture.samples.count / capture.channels) / capture.sampleRate
        return RecordedAudio(wavData: wav, duration: duration)
    }

    public func cancel() async { _ = stopAndTakeSamples() }

    private func stopAndTakeSamples() -> (samples: [Float], sampleRate: Double, channels: Int) {
        let wasRunning = lock.withLock { () -> Bool in
            let value = running
            running = false
            return value
        }
        if wasRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        return lock.withLock { (samples, sampleRate, max(channels, 1)) }
    }

    private func consume(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var incoming = [Float]()
        incoming.reserveCapacity(frameCount * channelCount)
        var squareSum: Float = 0
        for frame in 0..<frameCount {
            for channel in 0..<channelCount {
                let value = channelData[channel][frame]
                incoming.append(value)
                squareSum += value * value
            }
        }
        lock.withLock { if running { samples.append(contentsOf: incoming) } }
        let count = max(frameCount * channelCount, 1)
        onLevel(sqrt(squareSum / Float(count)))
    }

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            }
        @unknown default: return false
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T { lock(); defer { unlock() }; return body() }
}
