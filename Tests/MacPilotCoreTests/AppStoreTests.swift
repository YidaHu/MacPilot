import XCTest
@testable import MacPilotCore

final class AppStoreTests: XCTestCase {
    func testRefreshPublishesProviderSnapshot() async {
        let expected = SystemSnapshot(
            sampledAt: Date(timeIntervalSince1970: 0),
            cpuUsage: 0.25,
            memory: .init(usedBytes: 8, totalBytes: 16, pressure: .normal),
            disk: .init(availableBytes: 80, totalBytes: 100),
            network: .init(
                interfaceName: "en0",
                ipv4Address: "192.0.2.1",
                downloadBytesPerSecond: 10,
                uploadBytesPerSecond: 5,
                risk: .normal,
                riskExplanation: "Encrypted Wi-Fi"
            )
        )
        let store = await MainActor.run {
            AppStore(metrics: FakeMetrics(snapshot: expected))
        }

        await store.refresh()

        let actual = await MainActor.run { store.snapshot }
        XCTAssertEqual(actual, expected)
    }

    func testRefreshFailureKeepsLastGoodSnapshot() async {
        let expected = SystemSnapshot.fixture
        let provider = SequencedMetrics(results: [.success(expected), .failure(TestError.failed)])
        let store = await MainActor.run { AppStore(metrics: provider) }

        await store.refresh()
        await store.refresh()

        let state = await MainActor.run { (store.snapshot, store.lastErrorDescription) }
        XCTAssertEqual(state.0, expected)
        XCTAssertEqual(state.1, "failed")
    }
}

private struct FakeMetrics: MetricsProviding {
    let snapshot: SystemSnapshot
    func sample() async throws -> SystemSnapshot { snapshot }
}

private final class SequencedMetrics: MetricsProviding, @unchecked Sendable {
    private var results: [Result<SystemSnapshot, Error>]
    private let lock = NSLock()

    init(results: [Result<SystemSnapshot, Error>]) {
        self.results = results
    }

    func sample() async throws -> SystemSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return try results.removeFirst().get()
    }
}

private enum TestError: Error, LocalizedError {
    case failed
    var errorDescription: String? { "failed" }
}

private extension SystemSnapshot {
    static let fixture = SystemSnapshot(
        sampledAt: Date(timeIntervalSince1970: 1),
        cpuUsage: 0.5,
        memory: .init(usedBytes: 1, totalBytes: 2, pressure: .normal),
        disk: .init(availableBytes: 3, totalBytes: 4),
        network: .init(
            interfaceName: nil,
            ipv4Address: nil,
            downloadBytesPerSecond: 0,
            uploadBytesPerSecond: 0,
            risk: .unknown,
            riskExplanation: "Unavailable"
        )
    )
}
