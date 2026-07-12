import XCTest
@testable import MacPilotMetrics

final class CPUTicksTests: XCTestCase {
    func testCPUUsageUsesDeltaRatherThanLifetimeTicks() {
        let previous = CPUTicks(user: 100, system: 20, idle: 180, nice: 0)
        let current = CPUTicks(user: 150, system: 50, idle: 200, nice: 0)

        XCTAssertEqual(current.usage(since: previous), 0.8, accuracy: 0.0001)
    }

    func testCPUUsageReturnsZeroWhenNoTicksElapsed() {
        let ticks = CPUTicks(user: 100, system: 20, idle: 180, nice: 0)
        XCTAssertEqual(ticks.usage(since: ticks), 0)
    }

    func testCPUUsageClampsWhenCountersReset() {
        let previous = CPUTicks(user: 100, system: 100, idle: 100, nice: 0)
        let current = CPUTicks(user: 1, system: 1, idle: 1, nice: 0)
        XCTAssertEqual(current.usage(since: previous), 0)
    }
}
