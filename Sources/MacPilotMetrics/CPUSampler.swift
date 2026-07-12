import Darwin
import Foundation

public struct CPUTicks: Equatable, Sendable {
    public let user: UInt64
    public let system: UInt64
    public let idle: UInt64
    public let nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    public func usage(since previous: CPUTicks) -> Double {
        guard user >= previous.user,
              system >= previous.system,
              idle >= previous.idle,
              nice >= previous.nice else {
            return 0
        }

        let userDelta = user - previous.user
        let systemDelta = system - previous.system
        let idleDelta = idle - previous.idle
        let niceDelta = nice - previous.nice
        let busy = userDelta + systemDelta + niceDelta
        let total = busy + idleDelta
        guard total > 0 else { return 0 }
        return min(max(Double(busy) / Double(total), 0), 1)
    }
}

public enum CPUSamplerError: Error {
    case hostProcessorInfoFailed(kern_return_t)
    case missingProcessorInfo
}

public final class CPUSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var previous: CPUTicks?

    public init() {}

    public func sampleUsage() throws -> Double {
        let current = try readTicks()
        lock.lock()
        defer { lock.unlock() }
        let usage = previous.map { current.usage(since: $0) } ?? lifetimeUsage(current)
        previous = current
        return usage
    }

    public func readTicks() throws -> CPUTicks {
        var cpuCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )
        guard result == KERN_SUCCESS else {
            throw CPUSamplerError.hostProcessorInfoFailed(result)
        }
        guard let cpuInfo else {
            throw CPUSamplerError.missingProcessorInfo
        }
        defer {
            let size = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: cpuInfo)), size)
        }

        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0
        for cpu in 0..<Int(cpuCount) {
            let offset = Int(CPU_STATE_MAX) * cpu
            user += UInt64(cpuInfo[offset + Int(CPU_STATE_USER)])
            system += UInt64(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            idle += UInt64(cpuInfo[offset + Int(CPU_STATE_IDLE)])
            nice += UInt64(cpuInfo[offset + Int(CPU_STATE_NICE)])
        }
        return CPUTicks(user: user, system: system, idle: idle, nice: nice)
    }

    private func lifetimeUsage(_ ticks: CPUTicks) -> Double {
        let busy = ticks.user + ticks.system + ticks.nice
        let total = busy + ticks.idle
        guard total > 0 else { return 0 }
        return min(max(Double(busy) / Double(total), 0), 1)
    }
}
