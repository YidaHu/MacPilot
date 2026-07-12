import XCTest
@testable import MacPilotMetrics

final class MemoryMathTests: XCTestCase {
    func testMemoryUsedIncludesActiveWiredAndCompressedPages() {
        XCTAssertEqual(
            MemoryMath.usedBytes(active: 10, wired: 4, compressed: 2, pageSize: 4_096),
            65_536
        )
    }

    func testPressureThresholds() {
        XCTAssertEqual(MemoryMath.pressure(usedBytes: 60, totalBytes: 100), .normal)
        XCTAssertEqual(MemoryMath.pressure(usedBytes: 80, totalBytes: 100), .warning)
        XCTAssertEqual(MemoryMath.pressure(usedBytes: 95, totalBytes: 100), .critical)
        XCTAssertEqual(MemoryMath.pressure(usedBytes: 1, totalBytes: 0), .unknown)
    }
}
