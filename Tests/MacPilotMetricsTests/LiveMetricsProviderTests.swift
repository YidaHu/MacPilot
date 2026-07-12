import XCTest
@testable import MacPilotMetrics

final class LiveMetricsProviderTests: XCTestCase {
    func testLiveProviderReturnsPlausibleSystemValues() async throws {
        let snapshot = try await LiveMetricsProvider().sample()

        XCTAssertTrue((0...1).contains(snapshot.cpuUsage))
        XCTAssertGreaterThan(snapshot.memory.totalBytes, 0)
        XCTAssertLessThanOrEqual(snapshot.memory.usedBytes, snapshot.memory.totalBytes)
        XCTAssertGreaterThan(snapshot.disk.totalBytes, 0)
        XCTAssertLessThanOrEqual(snapshot.disk.availableBytes, snapshot.disk.totalBytes)
        XCTAssertNotNil(snapshot.network.interfaceName)
        XCTAssertFalse(snapshot.network.riskExplanation.isEmpty)
    }
}
