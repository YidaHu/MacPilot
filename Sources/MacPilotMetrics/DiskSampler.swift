import Foundation
import MacPilotCore

public enum DiskSamplerError: Error {
    case capacityUnavailable
}

public struct DiskSampler: Sendable {
    public init() {}

    public func sample() throws -> DiskSnapshot {
        let root = URL(fileURLWithPath: "/", isDirectory: true)
        let values = try root.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ])
        guard let totalValue = values.volumeTotalCapacity, totalValue >= 0 else {
            throw DiskSamplerError.capacityUnavailable
        }
        let availableValue = values.volumeAvailableCapacityForImportantUsage
            ?? values.volumeAvailableCapacity.map(Int64.init)
        guard let availableValue, availableValue >= 0 else {
            throw DiskSamplerError.capacityUnavailable
        }
        return DiskSnapshot(
            availableBytes: UInt64(availableValue),
            totalBytes: UInt64(totalValue)
        )
    }
}
