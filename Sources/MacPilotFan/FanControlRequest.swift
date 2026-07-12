@preconcurrency import Foundation

public enum FanControlMode: String, Equatable, Sendable {
    case automatic
    case manual
}

public struct ManualFanRequest: Equatable, Sendable {
    public let fanIndex: Int
    public let targetRPM: Double
    public let leaseID: UUID
    public let expiresAt: Date

    public init(fanIndex: Int, targetRPM: Double, leaseID: UUID, expiresAt: Date) {
        self.fanIndex = fanIndex
        self.targetRPM = targetRPM
        self.leaseID = leaseID
        self.expiresAt = expiresAt
    }
}
