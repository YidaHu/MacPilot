import Foundation

public enum SMCValueError: Error, Equatable {
    case invalidKey
    case invalidDataLength(expected: Int, actual: Int)
    case nonFiniteValue
    case valueOutOfRange
}

public struct SMCKey: Equatable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(_ string: String) throws {
        let bytes = Array(string.utf8)
        guard bytes.count == 4, bytes.allSatisfy({ $0 < 0x80 }) else {
            throw SMCValueError.invalidKey
        }
        rawValue = bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    public var stringValue: String {
        let bytes = [
            UInt8((rawValue >> 24) & 0xff),
            UInt8((rawValue >> 16) & 0xff),
            UInt8((rawValue >> 8) & 0xff),
            UInt8(rawValue & 0xff)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
}

public enum SMCValueCodec {
    public static func decodeFPE2(_ bytes: [UInt8]) throws -> Double {
        let raw = try unsigned16(bytes)
        return Double(raw) / 4
    }

    public static func encodeFPE2(_ value: Double) throws -> [UInt8] {
        guard value.isFinite else { throw SMCValueError.nonFiniteValue }
        let scaled = (value * 4).rounded()
        guard scaled >= 0, scaled <= Double(UInt16.max) else {
            throw SMCValueError.valueOutOfRange
        }
        let raw = UInt16(scaled)
        return [UInt8(raw >> 8), UInt8(raw & 0xff)]
    }

    public static func decodeSP78(_ bytes: [UInt8]) throws -> Double {
        let raw = try unsigned16(bytes)
        return Double(Int16(bitPattern: raw)) / 256
    }

    public static func decodeFLT(_ bytes: [UInt8]) throws -> Double {
        guard bytes.count == 4 else {
            throw SMCValueError.invalidDataLength(expected: 4, actual: bytes.count)
        }
        let raw = UInt32(bytes[0])
            | (UInt32(bytes[1]) << 8)
            | (UInt32(bytes[2]) << 16)
            | (UInt32(bytes[3]) << 24)
        let value = Double(Float(bitPattern: raw))
        guard value.isFinite else { throw SMCValueError.nonFiniteValue }
        guard value >= 0 else { throw SMCValueError.valueOutOfRange }
        return value
    }

    public static func encodeFLT(_ value: Double) throws -> [UInt8] {
        guard value.isFinite else { throw SMCValueError.nonFiniteValue }
        guard value >= 0 else { throw SMCValueError.valueOutOfRange }
        let floatValue = Float(value)
        guard floatValue.isFinite else { throw SMCValueError.valueOutOfRange }
        let raw = floatValue.bitPattern
        return [
            UInt8(raw & 0xff),
            UInt8((raw >> 8) & 0xff),
            UInt8((raw >> 16) & 0xff),
            UInt8(raw >> 24)
        ]
    }

    private static func unsigned16(_ bytes: [UInt8]) throws -> UInt16 {
        guard bytes.count == 2 else {
            throw SMCValueError.invalidDataLength(expected: 2, actual: bytes.count)
        }
        return (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
    }
}
