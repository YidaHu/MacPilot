@preconcurrency import Foundation

public protocol MetricsProviding: Sendable {
    func sample() async throws -> SystemSnapshot
}

public struct SystemSnapshot: Equatable, Sendable {
    public let sampledAt: Date
    public let cpuUsage: Double
    public let memory: MemorySnapshot
    public let disk: DiskSnapshot
    public let network: NetworkSnapshot

    public init(
        sampledAt: Date,
        cpuUsage: Double,
        memory: MemorySnapshot,
        disk: DiskSnapshot,
        network: NetworkSnapshot
    ) {
        self.sampledAt = sampledAt
        self.cpuUsage = cpuUsage
        self.memory = memory
        self.disk = disk
        self.network = network
    }

    public func isStale(at date: Date = Date(), threshold: TimeInterval) -> Bool {
        date.timeIntervalSince(sampledAt) > threshold
    }
}

public struct MemorySnapshot: Equatable, Sendable {
    public enum Pressure: Equatable, Sendable {
        case normal
        case warning
        case critical
        case unknown
    }

    public let usedBytes: UInt64
    public let totalBytes: UInt64
    public let pressure: Pressure

    public init(usedBytes: UInt64, totalBytes: UInt64, pressure: Pressure) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.pressure = pressure
    }
}

public struct DiskSnapshot: Equatable, Sendable {
    public let availableBytes: UInt64
    public let totalBytes: UInt64

    public init(availableBytes: UInt64, totalBytes: UInt64) {
        self.availableBytes = availableBytes
        self.totalBytes = totalBytes
    }
}

public struct NetworkSnapshot: Equatable, Sendable {
    public enum Risk: Equatable, Sendable {
        case normal
        case attention
        case unknown
    }

    public let interfaceName: String?
    public let ipv4Address: String?
    public let downloadBytesPerSecond: UInt64
    public let uploadBytesPerSecond: UInt64
    public let risk: Risk
    public let riskExplanation: String

    public init(
        interfaceName: String?,
        ipv4Address: String?,
        downloadBytesPerSecond: UInt64,
        uploadBytesPerSecond: UInt64,
        risk: Risk,
        riskExplanation: String
    ) {
        self.interfaceName = interfaceName
        self.ipv4Address = ipv4Address
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.risk = risk
        self.riskExplanation = riskExplanation
    }
}
