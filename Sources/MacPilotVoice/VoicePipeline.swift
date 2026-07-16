import Foundation

public actor VoicePipeline {
    public private(set) var state: VoicePipelineState = .idle

    private let audio: any AudioCapturing
    private let transcriber: any Transcribing
    private let polisher: any Polishing
    private let output: any TextOutputting
    private let history: any VoiceHistoryStoring
    private let context: VoiceContext
    private let configuration: VoicePipelineConfiguration
    private let onTransition: @Sendable (VoicePipelineState) -> Void
    private let onWarning: @Sendable (VoicePipelineWarning) -> Void
    private var activeSessionID: UUID?
    private var startingSessionID: UUID?

    public init(
        audio: any AudioCapturing,
        transcriber: any Transcribing,
        polisher: any Polishing,
        output: any TextOutputting,
        history: any VoiceHistoryStoring,
        context: VoiceContext = VoiceContext(),
        configuration: VoicePipelineConfiguration = VoicePipelineConfiguration(),
        onTransition: @escaping @Sendable (VoicePipelineState) -> Void = { _ in },
        onWarning: @escaping @Sendable (VoicePipelineWarning) -> Void = { _ in }
    ) {
        self.audio = audio
        self.transcriber = transcriber
        self.polisher = polisher
        self.output = output
        self.history = history
        self.context = context
        self.configuration = configuration
        self.onTransition = onTransition
        self.onWarning = onWarning
    }

    @discardableResult
    public func startRecording() async throws -> UUID {
        guard activeSessionID == nil, startingSessionID == nil else {
            throw VoicePipelineError.alreadyActive
        }
        let sessionID = UUID()
        activeSessionID = sessionID
        startingSessionID = sessionID
        transition(.init(stage: .recording, sessionID: sessionID))
        do {
            try await audio.start()
            try requireActive(sessionID)
            if startingSessionID == sessionID { startingSessionID = nil }
            return sessionID
        } catch {
            // start() may resume after an abort (for example after the system
            // microphone-permission sheet is dismissed). Always tear down any
            // engine that appeared after the earlier abort.
            await audio.cancel()
            if startingSessionID == sessionID { startingSessionID = nil }
            if activeSessionID == sessionID { finishSession() }
            throw error
        }
    }

    public func stopRecording() async throws {
        guard state.stage == .recording, let sessionID = activeSessionID else {
            throw VoicePipelineError.notRecording
        }

        do {
            let recording = try await audio.stop()
            try requireActive(sessionID)
            transition(.init(stage: .transcribing, sessionID: sessionID))

            let rawText = try await transcriber.transcribe(recording).trimmingCharacters(in: .whitespacesAndNewlines)
            try requireActive(sessionID)
            guard !rawText.isEmpty else { throw VoicePipelineError.emptyTranscript }
            let processed = try await process(rawText, sessionID: sessionID)
            let finalText = processed.text
            transition(.init(stage: .outputting, sessionID: sessionID, rawText: rawText, outputText: finalText))

            try await output.output(finalText)
            try requireActive(sessionID)
            try await history.save(.init(
                rawText: rawText,
                polishedText: finalText,
                duration: recording.duration,
                processingMode: processed.mode,
                processingStatus: processed.status
            ))
            try requireActive(sessionID)
            finishSession()
        } catch {
            if activeSessionID == sessionID { finishSession() }
            throw error
        }
    }

    public func abort() async {
        activeSessionID = nil
        transition(.idle)
        await audio.cancel()
    }

    private func requireActive(_ sessionID: UUID) throws {
        guard activeSessionID == sessionID else { throw VoicePipelineError.staleCompletion }
    }

    private func process(
        _ rawText: String,
        sessionID: UUID
    ) async throws -> (text: String, mode: VoiceProcessingMode, status: VoiceProcessingStatus) {
        guard configuration.polishEnabled else { return (rawText, .raw, .skipped) }
        let mode: VoiceProcessingMode = configuration.structuredDictation.enabled ? .structured : .standard
        transition(.init(
            stage: mode == .structured ? .structured : .polishing,
            sessionID: sessionID,
            rawText: rawText
        ))

        for attempt in 0..<3 {
            do {
                try Task.checkCancellation()
                let polished = try await polisher.polish(rawText, context: context)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                try requireActive(sessionID)
                let unusable = polished.isEmpty || (mode == .structured && rawText.count >= 500 && polished == rawText)
                if unusable {
                    if attempt == 0 { continue }
                    onWarning(.processingFallback(mode))
                    return (rawText, mode, .fallback)
                }
                return (polished, mode, .success)
            } catch {
                try requireActive(sessionID)
                if Task.isCancelled { throw CancellationError() }
                if Self.isRetryable(error), attempt < 2 { continue }
                onWarning(.processingFallback(mode))
                return (rawText, mode, .fallback)
            }
        }
        onWarning(.processingFallback(mode))
        return (rawText, mode, .fallback)
    }

    private static func isRetryable(_ error: Error) -> Bool {
        switch error {
        case LLMClientError.timeout, LLMClientError.rateLimited: return true
        case let LLMClientError.httpStatus(status): return (500...599).contains(status)
        default: return false
        }
    }

    private func finishSession() {
        activeSessionID = nil
        transition(.idle)
    }

    private func transition(_ newState: VoicePipelineState) {
        state = newState
        onTransition(newState)
    }
}
