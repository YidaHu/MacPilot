import XCTest
@testable import MacPilotVoice

final class VoicePipelineTests: XCTestCase {
    func testStructuredPipelinePublishesStructuredStageAndMetadata() async throws {
        let transitions = TransitionRecorder()
        let history = HistoryRecorder()
        let pipeline = VoicePipeline(
            audio: ImmediateAudioCapture(),
            transcriber: ImmediateTranscriber(text: "raw text"),
            polisher: ImmediatePolisher(text: "标题\n\n内容"),
            output: OutputRecorder(),
            history: history,
            configuration: .init(
                polishEnabled: true,
                structuredDictation: .init(enabled: true, prompt: "按主题整理")
            ),
            onTransition: { transitions.append($0.stage) }
        )

        _ = try await pipeline.startRecording()
        try await pipeline.stopRecording()

        XCTAssertEqual(transitions.values, [.recording, .transcribing, .structured, .outputting, .idle])
        XCTAssertEqual(history.values.first?.processingMode, .structured)
        XCTAssertEqual(history.values.first?.processingStatus, .success)
    }

    func testRetryablePolishFailureFallsBackToRawWithoutLosingSpeech() async throws {
        let output = OutputRecorder()
        let history = HistoryRecorder()
        let warnings = WarningRecorder()
        let polisher = ThrowingPolisher(error: LLMClientError.timeout)
        let pipeline = VoicePipeline(
            audio: ImmediateAudioCapture(),
            transcriber: ImmediateTranscriber(text: "raw transcript"),
            polisher: polisher,
            output: output,
            history: history,
            configuration: .init(polishEnabled: true, structuredDictation: .init(enabled: true)),
            onWarning: { warnings.append($0) }
        )

        _ = try await pipeline.startRecording()
        try await pipeline.stopRecording()

        XCTAssertEqual(polisher.callCount, 3)
        XCTAssertEqual(output.values, ["raw transcript"])
        XCTAssertEqual(history.values.first?.processingMode, .structured)
        XCTAssertEqual(history.values.first?.processingStatus, .fallback)
        XCTAssertEqual(warnings.values, [.processingFallback(.structured)])
    }

    func testLongUnchangedStructuredResponseRetriesOnceThenFallsBack() async throws {
        let raw = String(repeating: "长内容", count: 180)
        let polisher = ImmediatePolisher(text: raw)
        let history = HistoryRecorder()
        let pipeline = VoicePipeline(
            audio: ImmediateAudioCapture(),
            transcriber: ImmediateTranscriber(text: raw),
            polisher: polisher,
            output: OutputRecorder(),
            history: history,
            configuration: .init(polishEnabled: true, structuredDictation: .init(enabled: true))
        )

        _ = try await pipeline.startRecording()
        try await pipeline.stopRecording()

        XCTAssertEqual(polisher.callCount, 2)
        XCTAssertEqual(history.values.first?.processingStatus, .fallback)
    }

    func testAbortDuringPolishBlocksStaleOutput() async throws {
        let polisher = BlockingPolisher()
        let output = OutputRecorder()
        let pipeline = VoicePipeline(
            audio: ImmediateAudioCapture(),
            transcriber: ImmediateTranscriber(text: "raw"),
            polisher: polisher,
            output: output,
            history: HistoryRecorder(),
            configuration: .init(polishEnabled: true, structuredDictation: .init(enabled: true))
        )
        _ = try await pipeline.startRecording()
        let stopTask = Task { try await pipeline.stopRecording() }
        await polisher.waitUntilStarted()

        await pipeline.abort()
        await polisher.complete(with: "late result")

        do { try await stopTask.value; XCTFail("Expected stale completion") }
        catch { XCTAssertEqual(error as? VoicePipelineError, .staleCompletion) }
        XCTAssertTrue(output.values.isEmpty)
    }

    func testValidPipelineTransitionsInOrder() async throws {
        let transitions = TransitionRecorder()
        let output = OutputRecorder()
        let history = HistoryRecorder()
        let pipeline = VoicePipeline(
            audio: ImmediateAudioCapture(),
            transcriber: ImmediateTranscriber(text: "raw text"),
            polisher: ImmediatePolisher(text: "polished text"),
            output: output,
            history: history,
            onTransition: { transitions.append($0.stage) }
        )

        _ = try await pipeline.startRecording()
        try await pipeline.stopRecording()
        let finalState = await pipeline.state

        XCTAssertEqual(transitions.values, [.recording, .transcribing, .polishing, .outputting, .idle])
        XCTAssertEqual(output.values, ["polished text"])
        XCTAssertEqual(history.values.map(\.polishedText), ["polished text"])
        XCTAssertEqual(finalState.stage, .idle)
    }

    func testDoubleStartAndStopWhileIdleAreRejected() async throws {
        let pipeline = makePipeline()
        _ = try await pipeline.startRecording()

        do { _ = try await pipeline.startRecording(); XCTFail("Expected double-start rejection") }
        catch { XCTAssertEqual(error as? VoicePipelineError, .alreadyActive) }

        await pipeline.abort()
        do { try await pipeline.stopRecording(); XCTFail("Expected idle-stop rejection") }
        catch { XCTAssertEqual(error as? VoicePipelineError, .notRecording) }
    }

    func testStaleTranscriptionAfterAbortCannotReachOutput() async throws {
        let transcriber = BlockingTranscriber()
        let output = OutputRecorder()
        let pipeline = VoicePipeline(
            audio: ImmediateAudioCapture(),
            transcriber: transcriber,
            polisher: ImmediatePolisher(text: "must not output"),
            output: output,
            history: HistoryRecorder()
        )
        _ = try await pipeline.startRecording()
        let stopTask = Task { try await pipeline.stopRecording() }
        await transcriber.waitUntilStarted()

        await pipeline.abort()
        await transcriber.complete(with: "stale text")

        do { try await stopTask.value; XCTFail("Expected stale completion") }
        catch { XCTAssertEqual(error as? VoicePipelineError, .staleCompletion) }
        let finalState = await pipeline.state
        XCTAssertTrue(output.values.isEmpty)
        XCTAssertEqual(finalState.stage, .idle)
    }

    private func makePipeline() -> VoicePipeline {
        VoicePipeline(
            audio: ImmediateAudioCapture(),
            transcriber: ImmediateTranscriber(text: "raw"),
            polisher: ImmediatePolisher(text: "polished"),
            output: OutputRecorder(),
            history: HistoryRecorder()
        )
    }
}

private struct ImmediateAudioCapture: AudioCapturing {
    func start() async throws {}
    func stop() async throws -> RecordedAudio { RecordedAudio(wavData: Data([1, 2, 3]), duration: 1) }
    func cancel() async {}
}

private struct ImmediateTranscriber: Transcribing {
    let text: String
    func transcribe(_ audio: RecordedAudio) async throws -> String { text }
}

private actor BlockingTranscriber: Transcribing {
    private var continuation: CheckedContinuation<String, Error>?
    private var startedContinuations: [CheckedContinuation<Void, Never>] = []
    private var started = false

    func transcribe(_ audio: RecordedAudio) async throws -> String {
        started = true
        startedContinuations.forEach { $0.resume() }
        startedContinuations.removeAll()
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startedContinuations.append($0) }
    }

    func complete(with text: String) { continuation?.resume(returning: text); continuation = nil }
}

private final class ImmediatePolisher: @unchecked Sendable, Polishing {
    let text: String
    private let lock = NSLock()
    private var calls = 0
    var callCount: Int { lock.withLock { calls } }
    init(text: String) { self.text = text }
    func polish(_ rawText: String, context: VoiceContext) async throws -> String {
        lock.withLock { calls += 1 }
        return text
    }
}

private final class ThrowingPolisher: @unchecked Sendable, Polishing {
    let error: Error
    private let lock = NSLock()
    private var calls = 0
    var callCount: Int { lock.withLock { calls } }
    init(error: Error) { self.error = error }
    func polish(_ rawText: String, context: VoiceContext) async throws -> String {
        lock.withLock { calls += 1 }
        throw error
    }
}

private actor BlockingPolisher: Polishing {
    private var continuation: CheckedContinuation<String, Error>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var started = false
    func polish(_ rawText: String, context: VoiceContext) async throws -> String {
        started = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func complete(with text: String) { continuation?.resume(returning: text); continuation = nil }
}

private final class OutputRecorder: @unchecked Sendable, TextOutputting {
    private let lock = NSLock()
    private var storage: [String] = []
    var values: [String] { lock.withLock { storage } }
    func output(_ text: String) async throws { lock.withLock { storage.append(text) } }
}

private final class HistoryRecorder: @unchecked Sendable, VoiceHistoryStoring {
    private let lock = NSLock()
    private var storage: [VoiceHistoryEntry] = []
    var values: [VoiceHistoryEntry] { lock.withLock { storage } }
    func save(_ entry: VoiceHistoryEntry) async throws { lock.withLock { storage.append(entry) } }
}

private final class TransitionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [VoicePipelineStage] = []
    var values: [VoicePipelineStage] { lock.withLock { storage } }
    func append(_ stage: VoicePipelineStage) { lock.withLock { storage.append(stage) } }
}

private final class WarningRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [VoicePipelineWarning] = []
    var values: [VoicePipelineWarning] { lock.withLock { storage } }
    func append(_ warning: VoicePipelineWarning) { lock.withLock { storage.append(warning) } }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T { lock(); defer { unlock() }; return body() }
}
