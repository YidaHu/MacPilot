@preconcurrency import Foundation

public enum VoicePipelineStage: String, Equatable, Sendable {
    case idle
    case recording
    case transcribing
    case polishing
    case structured
    case outputting
}

public enum VoiceProcessingMode: String, Equatable, Sendable {
    case raw, standard, structured
}

public enum VoiceProcessingStatus: String, Equatable, Sendable {
    case success, skipped, fallback
}

public struct VoicePipelineConfiguration: Equatable, Sendable {
    public let polishEnabled: Bool
    public let structuredDictation: StructuredDictationSettings

    public init(polishEnabled: Bool = true, structuredDictation: StructuredDictationSettings = .disabled) {
        self.polishEnabled = polishEnabled
        self.structuredDictation = structuredDictation
    }
}

public enum VoicePipelineWarning: Equatable, Sendable {
    case processingFallback(VoiceProcessingMode)
}

public struct VoicePipelineState: Equatable, Sendable {
    public let stage: VoicePipelineStage
    public let sessionID: UUID?
    public let rawText: String?
    public let outputText: String?

    public init(stage: VoicePipelineStage, sessionID: UUID? = nil, rawText: String? = nil, outputText: String? = nil) {
        self.stage = stage
        self.sessionID = sessionID
        self.rawText = rawText
        self.outputText = outputText
    }

    public static let idle = VoicePipelineState(stage: .idle)
}

public struct RecordedAudio: Equatable, Sendable {
    public let wavData: Data
    public let duration: TimeInterval

    public init(wavData: Data, duration: TimeInterval) {
        self.wavData = wavData
        self.duration = duration
    }
}

public struct VoiceContext: Equatable, Sendable {
    public let sceneID: String?
    public let applicationName: String?

    public init(sceneID: String? = nil, applicationName: String? = nil) {
        self.sceneID = sceneID
        self.applicationName = applicationName
    }
}

public struct VoiceHistoryEntry: Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let rawText: String
    public let polishedText: String
    public let duration: TimeInterval
    public let processingMode: VoiceProcessingMode
    public let processingStatus: VoiceProcessingStatus

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        rawText: String,
        polishedText: String,
        duration: TimeInterval,
        processingMode: VoiceProcessingMode = .standard,
        processingStatus: VoiceProcessingStatus = .success
    ) {
        self.id = id
        self.createdAt = createdAt
        self.rawText = rawText
        self.polishedText = polishedText
        self.duration = duration
        self.processingMode = processingMode
        self.processingStatus = processingStatus
    }
}

public protocol AudioCapturing: Sendable {
    func start() async throws
    func stop() async throws -> RecordedAudio
    func cancel() async
}

public protocol Transcribing: Sendable {
    func transcribe(_ audio: RecordedAudio) async throws -> String
}

public protocol Polishing: Sendable {
    func polish(_ rawText: String, context: VoiceContext) async throws -> String
}

public protocol TextOutputting: Sendable {
    func output(_ text: String) async throws
}

public protocol VoiceHistoryStoring: Sendable {
    func save(_ entry: VoiceHistoryEntry) async throws
}

public enum VoicePipelineError: Error, Equatable {
    case alreadyActive
    case notRecording
    case staleCompletion
    case emptyTranscript
}
