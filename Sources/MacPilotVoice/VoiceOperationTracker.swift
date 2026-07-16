import Foundation

public struct VoiceOperationTracker {
    public private(set) var activeID: UUID?
    public var hasActiveOperation: Bool { activeID != nil }

    public init() {}

    @discardableResult
    public mutating func begin() -> UUID {
        let operationID = UUID()
        activeID = operationID
        return operationID
    }

    public mutating func cancel() {
        activeID = nil
    }

    public func isCurrent(_ operationID: UUID) -> Bool {
        activeID == operationID
    }

    @discardableResult
    public mutating func finish(_ operationID: UUID) -> Bool {
        guard activeID == operationID else { return false }
        activeID = nil
        return true
    }
}

public enum VoiceOperationDecision: Equatable {
    case accepted(UUID)
    case rejected(recording: Bool)
}

public struct VoiceOperationCoordinator {
    private enum SessionPhase {
        case idle
        case starting
        case recording
        case processing
    }

    private var tracker = VoiceOperationTracker()
    private var activeAction: HotKeyAction?
    private var sessionPhase: SessionPhase = .idle

    public var activeOperationID: UUID? { tracker.activeID }
    public var isRecordingSession: Bool { sessionPhase == .recording }
    public var canToggleRecording: Bool {
        guard !tracker.hasActiveOperation else { return false }
        return sessionPhase == .idle || sessionPhase == .recording
    }

    public init() {}

    public mutating func begin(
        _ action: HotKeyAction,
        during stage: VoicePipelineStage
    ) -> VoiceOperationDecision {
        guard !tracker.hasActiveOperation else {
            return .rejected(recording: isRecordingSession)
        }

        switch action {
        case .startRecording:
            guard sessionPhase == .idle, stage == .idle else {
                return .rejected(recording: isRecordingSession)
            }
            sessionPhase = .starting
        case .stopRecording:
            guard sessionPhase == .recording, stage == .recording else {
                return .rejected(recording: isRecordingSession)
            }
            // This lock is held for the entire transcription, admission,
            // structured-generation, output and history-save operation.
            sessionPhase = .processing
        case .none:
            guard HotKeyActionPolicy.isAllowed(action, during: stage) else {
                return .rejected(recording: isRecordingSession)
            }
        }

        activeAction = action
        return .accepted(tracker.begin())
    }

    public mutating func cancel() {
        tracker.cancel()
        activeAction = nil
        sessionPhase = .idle
    }

    public func shouldPresentError(for operationID: UUID, taskIsCancelled: Bool) -> Bool {
        !taskIsCancelled && tracker.isCurrent(operationID)
    }

    @discardableResult
    public mutating func finish(_ operationID: UUID, succeeded: Bool = true) -> Bool {
        guard tracker.finish(operationID) else { return false }
        let finishedAction = activeAction
        activeAction = nil
        switch finishedAction {
        case .startRecording:
            sessionPhase = succeeded ? .recording : .idle
        case .stopRecording:
            sessionPhase = .idle
        case .some(.none), nil:
            break
        }
        return true
    }
}

public enum VoiceRuntimeRebuildDecision: Equatable {
    case rebuild(UUID)
    case deferred
}

/// Keeps a running voice pipeline stable until its current recording or
/// processing operation has returned to idle. Runtime-setting changes are
/// collapsed into one replacement so callbacks from an older pipeline cannot
/// race a newly-created pipeline.
public struct VoiceRuntimeCoordinator {
    private var generation: UUID?
    private var hasDeferredRebuild = false

    public init() {}

    public mutating func requestRebuild(
        during stage: VoicePipelineStage,
        transitionPending: Bool = false
    ) -> VoiceRuntimeRebuildDecision {
        guard stage == .idle, !transitionPending else {
            hasDeferredRebuild = true
            return .deferred
        }
        return .rebuild(advanceGeneration())
    }

    public mutating func takeDeferredRebuild(during stage: VoicePipelineStage) -> UUID? {
        guard stage == .idle, hasDeferredRebuild else { return nil }
        hasDeferredRebuild = false
        return advanceGeneration()
    }

    public func accepts(_ candidate: UUID) -> Bool {
        generation == candidate
    }

    private mutating func advanceGeneration() -> UUID {
        let replacement = UUID()
        generation = replacement
        return replacement
    }
}
