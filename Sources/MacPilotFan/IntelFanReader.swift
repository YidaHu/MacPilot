import Foundation

public enum SMCReadError: Error, Equatable {
    case keyNotFound(String)
    case unsupportedFanCount(Int)
    case malformedValue(String)
    case connectionFailed(Int32)
    case callFailed(Int32)
    case smcResult(UInt8)
}

public protocol SMCKeyReading {
    func read(_ key: SMCKey) throws -> [UInt8]
}

public protocol SMCKeyWriting {
    func write(_ key: SMCKey, bytes: [UInt8]) throws
}

public protocol SMCKeyAccessing: SMCKeyReading, SMCKeyWriting {}

public struct IntelFanReader {
    private let reader: any SMCKeyReading

    public init(reader: any SMCKeyReading) {
        self.reader = reader
    }

    public func readSnapshot() throws -> FanSnapshot {
        let countData = try reader.read(SMCKey("FNum"))
        guard let first = countData.first else { throw SMCReadError.malformedValue("FNum") }
        let count = Int(first)
        guard (1...4).contains(count) else { throw SMCReadError.unsupportedFanCount(count) }

        return FanSnapshot(fans: try (0..<count).map(readFan))
    }

    private func readFan(index: Int) throws -> FanStatus {
        let prefix = "F\(index)"
        let actual = try readRPM(prefix + "Ac")
        let target = try? readRPM(prefix + "Tg")
        let minimum = try? readRPM(prefix + "Mn")
        let maximum = try? readRPM(prefix + "Mx")

        let availability: FanControlAvailability
        if let minimum, let maximum {
            availability = minimum < maximum ? .available : .unavailable("安全转速范围无效")
        } else {
            availability = .unavailable("无法验证安全转速范围")
        }

        return FanStatus(
            index: index,
            actualRPM: actual,
            minimumRPM: minimum,
            maximumRPM: maximum,
            targetRPM: target,
            controlAvailability: availability
        )
    }

    private func readRPM(_ key: String) throws -> Double {
        let bytes = try reader.read(SMCKey(key))
        switch bytes.count {
        case 2: return try SMCValueCodec.decodeFPE2(bytes)
        case 4: return try SMCValueCodec.decodeFLT(bytes)
        default: throw SMCReadError.malformedValue(key)
        }
    }
}
