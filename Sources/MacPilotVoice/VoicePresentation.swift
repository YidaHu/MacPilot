import Foundation

public enum CapsuleDisplayState: Equatable, Sendable {
    case idle
    case recording(level: Float, elapsed: TimeInterval)
    case transcribing
    case polishing
    case structured
    case outputting
    case complete
    case error(message: String, collapsed: Bool)
}

public struct CapsuleSize: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct CapsulePoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct CapsuleRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum CapsuleLayout {
    public static func isVisible(state: CapsuleDisplayState, autoHide: Bool) -> Bool {
        state != .idle || !autoHide
    }

    public static func size(for state: CapsuleDisplayState) -> CapsuleSize {
        switch state {
        case .idle: return .init(width: 36, height: 36)
        case .recording: return .init(width: 200, height: 36)
        case .transcribing, .polishing, .structured: return .init(width: 220, height: 36)
        case .outputting: return .init(width: 150, height: 36)
        case .complete: return .init(width: 100, height: 36)
        case let .error(_, collapsed): return .init(width: collapsed ? 36 : 200, height: 36)
        }
    }

    public static func defaultOrigin(size: CapsuleSize, visibleFrame: CapsuleRect) -> CapsulePoint {
        clamp(
            origin: .init(
                x: visibleFrame.x + (visibleFrame.width - size.width) / 2,
                y: visibleFrame.y + 80
            ),
            size: size,
            visibleFrame: visibleFrame
        )
    }

    public static func clamp(origin: CapsulePoint, size: CapsuleSize, visibleFrame: CapsuleRect) -> CapsulePoint {
        let maximumX = max(visibleFrame.x, visibleFrame.x + visibleFrame.width - size.width)
        let maximumY = max(visibleFrame.y, visibleFrame.y + visibleFrame.height - size.height)
        return .init(
            x: min(max(origin.x, visibleFrame.x), maximumX),
            y: min(max(origin.y, visibleFrame.y), maximumY)
        )
    }
}

public struct VoicePresentationAdapter: Sendable {
    public private(set) var displayState: CapsuleDisplayState = .idle
    private var previousStage: VoicePipelineStage = .idle

    public init() {}

    @discardableResult
    public mutating func consume(_ state: VoicePipelineState) -> CapsuleDisplayState {
        switch state.stage {
        case .idle:
            displayState = previousStage == .outputting ? .complete : .idle
        case .recording:
            displayState = .recording(level: 0, elapsed: 0)
        case .transcribing:
            displayState = .transcribing
        case .polishing:
            displayState = .polishing
        case .structured:
            displayState = .structured
        case .outputting:
            displayState = .outputting
        }
        previousStage = state.stage
        return displayState
    }

    public mutating func updateRecording(level: Float, elapsed: TimeInterval) {
        guard case .recording = displayState else { return }
        displayState = .recording(level: min(max(level, 0), 1), elapsed: max(elapsed, 0))
    }

    public mutating func markFailed(_ message: String) {
        displayState = .error(message: message, collapsed: false)
    }

    public mutating func collapseError() {
        guard case let .error(message, _) = displayState else { return }
        displayState = .error(message: message, collapsed: true)
    }

    public mutating func resetToIdle() {
        previousStage = .idle
        displayState = .idle
    }
}
