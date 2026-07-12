import XCTest
@testable import MacPilotCore

final class PlaceholderCoreTests: XCTestCase {
    func testModuleVersionIsNotEmpty() {
        XCTAssertFalse(MacPilotCoreModule.version.isEmpty)
    }
}
