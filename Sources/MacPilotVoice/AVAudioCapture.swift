import AVFoundation
import Foundation

public struct AudioCaptureLifecycle {
    public var isRunning: Bool { activeGeneration != nil }
    public private(set) var activeGeneration: Int?
    private var generation = 0

    public init() {}

    public mutating func begin() -> Int? {
        guard !isRunning else { return nil }
        generation += 1
        activeGeneration = generation
        return generation
    }

    @discardableResult
    public mutating func end(_ candidate: Int) -> Bool {
        guard activeGeneration == candidate else { return false }
        activeGeneration = nil
        return true
    }

    public func isCurrent(_ candidate: Int) -> Bool {
        activeGeneration == candidate
    }
}

public enum AudioTapFormatPolicy {
    public static func installationFormat(for _: AVAudioFormat) -> AVAudioFormat? {
        // Passing an explicit format to an input-node tap can abort the process when
        // Bluetooth hardware reports a different sample rate after routing or wake.
        // A nil format makes AVAudioEngine negotiate the node's native format safely.
        nil
    }
}

public final class AVAudioCapture: @unchecked Sendable, AudioCapturing {
    private let stateLock = NSLock()
    private let graphLock = NSLock()
    private let maximumDuration: TimeInterval
    private let onLevel: @Sendable (Float) -> Void
    private var engine: AVAudioEngine?
    private var lifecycle = AudioCaptureLifecycle()
    private var samples: [Float] = []
    private var sampleRate: Double = 0
    private var channels = 0

    public init(maximumDuration: TimeInterval = 30, onLevel: @escaping @Sendable (Float) -> Void = { _ in }) {
        self.maximumDuration = maximumDuration
        self.onLevel = onLevel
    }

    public func start() async throws {
        guard await requestMicrophoneAccess() else { throw AudioCaptureError.microphonePermissionDenied }
        try Task.checkCancellation()

        // Serialize graph installation and teardown. VoicePipeline is an actor,
        // but its async calls are reentrant and cancellation can arrive while a
        // start is still completing.
        graphLock.lock()
        defer { graphLock.unlock() }
        guard let generation = stateLock.withLock({ lifecycle.begin() }) else {
            throw AudioCaptureError.engineUnavailable
        }

        // AVAudioEngine keeps hardware formats from the device graph it was created with.
        // Build a fresh graph for every recording so a sleep/wake or input-device change
        // cannot leave us installing a tap on a stale audio node.
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            _ = stateLock.withLock { lifecycle.end(generation) }
            throw AudioCaptureError.invalidFormat
        }

        stateLock.withLock {
            samples.removeAll(keepingCapacity: true)
            sampleRate = format.sampleRate
            channels = Int(format.channelCount)
            self.engine = engine
        }
        input.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: AudioTapFormatPolicy.installationFormat(for: format)
        ) { [weak self] buffer, _ in
            self?.consume(buffer, generation: generation)
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            engine.stop()
            stateLock.withLock {
                if lifecycle.isCurrent(generation) {
                    if self.engine === engine { self.engine = nil }
                    lifecycle.end(generation)
                }
            }
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
        graphLock.lock()
        defer { graphLock.unlock() }
        let capture = stateLock.withLock { () -> (AVAudioEngine?, [Float], Double, Int) in
            guard let generation = lifecycle.activeGeneration else {
                return (nil, samples, sampleRate, max(channels, 1))
            }
            lifecycle.end(generation)
            let currentEngine = self.engine
            self.engine = nil
            return (currentEngine, samples, sampleRate, max(channels, 1))
        }
        let engine = capture.0
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engine.reset()
        }
        return (capture.1, capture.2, capture.3)
    }

    private func consume(_ buffer: AVAudioPCMBuffer, generation: Int) {
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
        let accepted = stateLock.withLock { () -> Bool in
            guard lifecycle.isCurrent(generation) else { return false }
            if samples.isEmpty {
                // With a nil tap format, the callback format is the authoritative
                // post-routing format and may differ from the node snapshot above.
                sampleRate = buffer.format.sampleRate
                channels = channelCount
            }
            samples.append(contentsOf: incoming)
            return true
        }
        guard accepted else { return }
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
