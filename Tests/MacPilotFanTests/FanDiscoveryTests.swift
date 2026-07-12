import XCTest
@testable import MacPilotFan

final class FanDiscoveryTests: XCTestCase {
    func testDiscoversTwoFansAndTheirVerifiedRanges() throws {
        let reader = DictionarySMCReader(values: [
            "FNum": [2],
            "F0Ac": fpe2(2_000), "F0Mn": fpe2(1_200), "F0Mx": fpe2(5_900), "F0Tg": fpe2(2_100),
            "F1Ac": fpe2(2_100), "F1Mn": fpe2(1_200), "F1Mx": fpe2(5_500), "F1Tg": fpe2(2_200)
        ])

        let snapshot = try IntelFanReader(reader: reader).readSnapshot()

        XCTAssertEqual(snapshot.fans.count, 2)
        XCTAssertEqual(snapshot.fans[0], FanStatus(index: 0, actualRPM: 2_000, minimumRPM: 1_200, maximumRPM: 5_900, targetRPM: 2_100, controlAvailability: .available))
        XCTAssertEqual(snapshot.fans[1].maximumRPM, 5_500)
        XCTAssertTrue(snapshot.controlsAvailable)
    }

    func testMissingVerifiedBoundKeepsMetricsButDisablesControls() throws {
        let reader = DictionarySMCReader(values: [
            "FNum": [1], "F0Ac": fpe2(2_000), "F0Mn": fpe2(1_200), "F0Tg": fpe2(2_100)
        ])

        let snapshot = try IntelFanReader(reader: reader).readSnapshot()

        XCTAssertEqual(snapshot.fans[0].actualRPM, 2_000)
        XCTAssertEqual(snapshot.fans[0].controlAvailability, .unavailable("无法验证安全转速范围"))
        XCTAssertFalse(snapshot.controlsAvailable)
    }

    func testInvalidRangeDisablesControls() throws {
        let reader = DictionarySMCReader(values: [
            "FNum": [1], "F0Ac": fpe2(2_000), "F0Mn": fpe2(5_000), "F0Mx": fpe2(5_000), "F0Tg": fpe2(2_100)
        ])

        let snapshot = try IntelFanReader(reader: reader).readSnapshot()

        XCTAssertEqual(snapshot.fans[0].controlAvailability, .unavailable("安全转速范围无效"))
    }

    func testDiscoversFloatEncodedFanValues() throws {
        let reader = DictionarySMCReader(values: [
            "FNum": [1], "F0Ac": flt(2_000), "F0Mn": flt(1_200), "F0Mx": flt(5_900), "F0Tg": flt(2_100)
        ])

        let fan = try IntelFanReader(reader: reader).readSnapshot().fans[0]

        XCTAssertEqual(fan.actualRPM, 2_000)
        XCTAssertEqual(fan.minimumRPM, 1_200)
        XCTAssertEqual(fan.maximumRPM, 5_900)
    }

    func testFanCountOutsideSupportedRangeIsRejected() {
        XCTAssertThrowsError(try IntelFanReader(reader: DictionarySMCReader(values: ["FNum": [9]])).readSnapshot())
    }

    private func fpe2(_ value: Double) -> [UInt8] {
        try! SMCValueCodec.encodeFPE2(value)
    }

    private func flt(_ value: Float) -> [UInt8] {
        let raw = value.bitPattern.littleEndian
        return withUnsafeBytes(of: raw) { Array($0) }
    }
}

private struct DictionarySMCReader: SMCKeyReading {
    let values: [String: [UInt8]]

    func read(_ key: SMCKey) throws -> [UInt8] {
        guard let value = values[key.stringValue] else { throw SMCReadError.keyNotFound(key.stringValue) }
        return value
    }
}
