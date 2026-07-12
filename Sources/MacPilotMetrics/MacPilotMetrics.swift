import Foundation
import MacPilotCore

public enum MacPilotMetricsModule {
    public static let version = MacPilotCoreModule.version
}

public final class LiveMetricsProvider: MetricsProviding, @unchecked Sendable {
    private let cpu = CPUSampler()
    private let memory = MemorySampler()
    private let disk = DiskSampler()
    private let network = NetworkSampler()

    public init() {}

    public func sample() async throws -> SystemSnapshot {
        SystemSnapshot(
            sampledAt: Date(),
            cpuUsage: try cpu.sampleUsage(),
            memory: try memory.sample(),
            disk: try disk.sample(),
            network: try network.sample()
        )
    }
}
