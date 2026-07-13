import Foundation

public struct RecordingDeadline: Equatable, Sendable {
    public let limit: TimeInterval

    private var triggered = false

    public init(limit: TimeInterval) {
        self.limit = limit
    }

    public mutating func consume(elapsed: TimeInterval) -> Bool {
        guard !triggered, elapsed >= limit else {
            return false
        }

        triggered = true
        return true
    }

    public mutating func reset() {
        triggered = false
    }
}
