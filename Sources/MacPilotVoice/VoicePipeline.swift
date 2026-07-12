import Foundation

public actor VoicePipeline {
    public private(set) var state: VoicePipelineState = .idle

    private let audio: any AudioCapturing
    private let transcriber: any Transcribing
    private let polisher: any Polishing
    private let output: any TextOutputting
    private let history: any VoiceHistoryStoring
    private let context: VoiceContext
    private let onTransition: @Sendable (VoicePipelineState) -> Void
    private var activeSessionID: UUID?

    public init(
        audio: any AudioCapturing,
        transcriber: any Transcribing,
        polisher: any Polishing,
        output: any TextOutputting,
        history: any VoiceHistoryStoring,
        context: VoiceContext = VoiceContext(),
        onTransition: @escaping @Sendable (VoicePipelineState) -> Void = { _ in }
    ) {
        self.audio = audio
        self.transcriber = transcriber
        self.polisher = polisher
        self.output = output
        self.history = history
        self.context = context
        self.onTransition = onTransition
    }

    @discardableResult
    public func startRecording() async throws -> UUID {
        guard activeSessionID == nil else { throw VoicePipelineError.alreadyActive }
        let sessionID = UUID()
        activeSessionID = sessionID
        transition(.init(stage: .recording, sessionID: sessionID))
        do {
            try await audio.start()
            try requireActive(sessionID)
            return sessionID
        } catch {
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
            transition(.init(stage: .polishing, sessionID: sessionID, rawText: rawText))

            let polished = try await polisher.polish(rawText, context: context).trimmingCharacters(in: .whitespacesAndNewlines)
            try requireActive(sessionID)
            let finalText = polished.isEmpty ? rawText : polished
            transition(.init(stage: .outputting, sessionID: sessionID, rawText: rawText, outputText: finalText))

            try await output.output(finalText)
            try requireActive(sessionID)
            try await history.save(.init(rawText: rawText, polishedText: finalText, duration: recording.duration))
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

    private func finishSession() {
        activeSessionID = nil
        transition(.idle)
    }

    private func transition(_ newState: VoicePipelineState) {
        state = newState
        onTransition(newState)
    }
}
