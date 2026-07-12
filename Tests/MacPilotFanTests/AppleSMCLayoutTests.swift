import XCTest
@testable import MacPilotFan

final class AppleSMCLayoutTests: XCTestCase {
    func testKernelCallStructureMatchesAppleSMCABI() {
        XCTAssertEqual(SMCABI.structureStride, 80)
        XCTAssertEqual(SMCABI.keyInfoOffset, 28)
        XCTAssertEqual(SMCABI.resultOffset, 40)
        XCTAssertEqual(SMCABI.commandOffset, 42)
        XCTAssertEqual(SMCABI.data32Offset, 44)
        XCTAssertEqual(SMCABI.bytesOffset, 48)
    }
}
