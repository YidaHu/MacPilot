import XCTest
@testable import MacPilotMetrics

final class PlaceholderMetricsTests: XCTestCase {
    func testModuleVersionMatchesCore() {
        XCTAssertEqual(MacPilotMetricsModule.version, "0.1.0")
    }
}
