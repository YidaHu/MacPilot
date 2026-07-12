@preconcurrency import Foundation

public enum FanControlAvailability: Equatable, Sendable {
    case available
    case unavailable(String)
}

public struct FanStatus: Equatable, Sendable, Identifiable {
    public let index: Int
    public let actualRPM: Double
    public let minimumRPM: Double?
    public let maximumRPM: Double?
    public let targetRPM: Double?
    public let controlAvailability: FanControlAvailability

    public var id: Int { index }

    public init(index: Int, actualRPM: Double, minimumRPM: Double?, maximumRPM: Double?, targetRPM: Double?, controlAvailability: FanControlAvailability) {
        self.index = index
        self.actualRPM = actualRPM
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
        self.targetRPM = targetRPM
        self.controlAvailability = controlAvailability
    }
}

public struct FanSnapshot: Equatable, Sendable {
    public let fans: [FanStatus]
    public let sampledAt: Date

    public init(fans: [FanStatus], sampledAt: Date = Date()) {
        self.fans = fans
        self.sampledAt = sampledAt
    }

    public var controlsAvailable: Bool {
        !fans.isEmpty && fans.allSatisfy { $0.controlAvailability == .available }
    }
}
