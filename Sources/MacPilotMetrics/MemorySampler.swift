import Darwin
import Foundation
import MacPilotCore

public enum MemoryMath {
    public static func usedBytes(
        active: UInt64,
        wired: UInt64,
        compressed: UInt64,
        pageSize: UInt64
    ) -> UInt64 {
        (active + wired + compressed) * pageSize
    }

    public static func pressure(
        usedBytes: UInt64,
        totalBytes: UInt64
    ) -> MemorySnapshot.Pressure {
        guard totalBytes > 0 else { return .unknown }
        let ratio = Double(usedBytes) / Double(totalBytes)
        if ratio >= 0.9 { return .critical }
        if ratio >= 0.75 { return .warning }
        return .normal
    }
}

public enum MemorySamplerError: Error {
    case hostStatisticsFailed(kern_return_t)
    case pageSizeFailed(kern_return_t)
}

public struct MemorySampler: Sendable {
    public init() {}

    public func sample() throws -> MemorySnapshot {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let statisticsResult = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard statisticsResult == KERN_SUCCESS else {
            throw MemorySamplerError.hostStatisticsFailed(statisticsResult)
        }

        var pageSize: vm_size_t = 0
        let pageSizeResult = host_page_size(mach_host_self(), &pageSize)
        guard pageSizeResult == KERN_SUCCESS else {
            throw MemorySamplerError.pageSizeFailed(pageSizeResult)
        }

        let used = MemoryMath.usedBytes(
            active: UInt64(statistics.active_count),
            wired: UInt64(statistics.wire_count),
            compressed: UInt64(statistics.compressor_page_count),
            pageSize: UInt64(pageSize)
        )
        let total = ProcessInfo.processInfo.physicalMemory
        return MemorySnapshot(
            usedBytes: min(used, total),
            totalBytes: total,
            pressure: MemoryMath.pressure(usedBytes: used, totalBytes: total)
        )
    }
}
