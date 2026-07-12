import Foundation

public enum FanRequestValidationError: Error, Equatable {
    case unknownFan(Int)
    case nonFiniteRPM
    case rpmOutsideVerifiedRange
    case expiredLease
    case leaseTooLong
    case rateLimited
    case unsupportedMode(String)
}

public struct FanRequestValidator: Sendable {
    private let ranges: [Int: ClosedRange<Double>]
    private let minimumRequestInterval: TimeInterval
    private let maximumLeaseDuration: TimeInterval

    public init(ranges: [Int: ClosedRange<Double>], minimumRequestInterval: TimeInterval = 0.1, maximumLeaseDuration: TimeInterval = 10) {
        self.ranges = ranges
        self.minimumRequestInterval = minimumRequestInterval
        self.maximumLeaseDuration = maximumLeaseDuration
    }

    public func validateManual(fanIndex: Int, targetRPM: Double, expiresAt: Date, now: Date, lastRequestAt: Date?) throws {
        guard let range = ranges[fanIndex] else { throw FanRequestValidationError.unknownFan(fanIndex) }
        guard targetRPM.isFinite else { throw FanRequestValidationError.nonFiniteRPM }
        guard range.contains(targetRPM) else { throw FanRequestValidationError.rpmOutsideVerifiedRange }
        let duration = expiresAt.timeIntervalSince(now)
        guard duration > 0 else { throw FanRequestValidationError.expiredLease }
        guard duration <= maximumLeaseDuration else { throw FanRequestValidationError.leaseTooLong }
        if let lastRequestAt, now.timeIntervalSince(lastRequestAt) < minimumRequestInterval {
            throw FanRequestValidationError.rateLimited
        }
    }

    public func validateMode(_ rawValue: String) throws -> FanControlMode {
        guard let mode = FanControlMode(rawValue: rawValue) else {
            throw FanRequestValidationError.unsupportedMode(rawValue)
        }
        return mode
    }
}
