import XCTest
@testable import MacPilotFan

final class SMCValueTests: XCTestCase {
    func testFPE2DecodesFanSpeed() throws {
        XCTAssertEqual(try SMCValueCodec.decodeFPE2([0x17, 0x70]), 1_500)
    }

    func testFPE2RoundTripsFiniteFanSpeed() throws {
        let encoded = try SMCValueCodec.encodeFPE2(2_345.25)
        XCTAssertEqual(try SMCValueCodec.decodeFPE2(encoded), 2_345.25, accuracy: 0.25)
    }

    func testSP78DecodesPositiveAndNegativeTemperatures() throws {
        XCTAssertEqual(try SMCValueCodec.decodeSP78([0x19, 0x80]), 25.5)
        XCTAssertEqual(try SMCValueCodec.decodeSP78([0xFB, 0x00]), -5)
    }

    func testKeyRequiresExactlyFourASCIICharacters() throws {
        XCTAssertEqual(try SMCKey("F0Ac").stringValue, "F0Ac")
        XCTAssertThrowsError(try SMCKey("Fan"))
        XCTAssertThrowsError(try SMCKey("风扇AB"))
    }

    func testShortBuffersAreRejected() {
        XCTAssertThrowsError(try SMCValueCodec.decodeFPE2([0x17]))
        XCTAssertThrowsError(try SMCValueCodec.decodeSP78([]))
    }

    func testNonFiniteAndOutOfRangeValuesAreRejected() {
        XCTAssertThrowsError(try SMCValueCodec.encodeFPE2(.nan))
        XCTAssertThrowsError(try SMCValueCodec.encodeFPE2(.infinity))
        XCTAssertThrowsError(try SMCValueCodec.encodeFPE2(-1))
        XCTAssertThrowsError(try SMCValueCodec.encodeFPE2(20_000))
    }
}
