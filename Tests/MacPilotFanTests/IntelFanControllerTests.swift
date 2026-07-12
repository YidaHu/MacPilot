import XCTest
@testable import MacPilotFan
@testable import MacPilotFanHelper

final class IntelFanControllerTests: XCTestCase {
    func testManualControlWritesOnlyVerifiedTargetAndModeKeys() throws {
        let smc = RecordingSMC(values: fixture())
        let controller = try IntelFanController(smc: smc)

        try controller.setManual(fanIndex: 0, targetRPM: 3_000)

        XCTAssertEqual(smc.writes.map(\.key), ["F0Tg", "F0Md"])
        XCTAssertEqual(try SMCValueCodec.decodeFLT(smc.writes[0].bytes), 3_000)
        XCTAssertEqual(smc.writes[1].bytes, [1])
    }

    func testRestoreWritesAutomaticModeOnlyForRequestedFan() throws {
        let smc = RecordingSMC(values: fixture())
        let controller = try IntelFanController(smc: smc)

        try controller.restoreAutomatic(fanIndices: [1])

        XCTAssertEqual(smc.writes, [SMCWriteRecord(key: "F1Md", bytes: [0])])
    }

    private func fixture() -> [String: [UInt8]] {
        [
            "FNum": [2],
            "F0Ac": flt(2_000), "F0Mn": flt(1_200), "F0Mx": flt(5_900), "F0Tg": flt(2_100),
            "F1Ac": flt(2_100), "F1Mn": flt(1_200), "F1Mx": flt(5_500), "F1Tg": flt(2_200),
            "F0Md": [0], "F1Md": [0]
        ]
    }

    private func flt(_ value: Float) -> [UInt8] {
        let raw = value.bitPattern
        return [UInt8(raw & 0xff), UInt8((raw >> 8) & 0xff), UInt8((raw >> 16) & 0xff), UInt8(raw >> 24)]
    }
}

private struct SMCWriteRecord: Equatable {
    let key: String
    let bytes: [UInt8]
}

private final class RecordingSMC: SMCKeyAccessing {
    let values: [String: [UInt8]]
    var writes: [SMCWriteRecord] = []

    init(values: [String: [UInt8]]) { self.values = values }

    func read(_ key: SMCKey) throws -> [UInt8] {
        guard let value = values[key.stringValue] else { throw SMCReadError.keyNotFound(key.stringValue) }
        return value
    }

    func write(_ key: SMCKey, bytes: [UInt8]) throws {
        writes.append(SMCWriteRecord(key: key.stringValue, bytes: bytes))
    }
}
