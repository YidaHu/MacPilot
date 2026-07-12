import Foundation
import MacPilotFan

public enum IntelFanControllerError: Error, Equatable {
    case unverifiedModeKey(Int)
    case unsupportedTargetEncoding(Int)
}

public final class IntelFanController: FanAutomaticRestoring {
    private enum TargetEncoding { case fpe2, flt }

    private let smc: any SMCKeyAccessing
    private let ranges: [Int: ClosedRange<Double>]
    private let encodings: [Int: TargetEncoding]
    private let automaticModeValues: [Int: [UInt8]]

    public init(smc: any SMCKeyAccessing) throws {
        self.smc = smc
        let snapshot = try IntelFanReader(reader: smc).readSnapshot()
        var ranges: [Int: ClosedRange<Double>] = [:]
        var encodings: [Int: TargetEncoding] = [:]
        var modes: [Int: [UInt8]] = [:]

        for fan in snapshot.fans {
            guard let minimum = fan.minimumRPM, let maximum = fan.maximumRPM, minimum < maximum else {
                throw IntelFanControllerError.unsupportedTargetEncoding(fan.index)
            }
            let targetBytes = try smc.read(SMCKey("F\(fan.index)Tg"))
            switch targetBytes.count {
            case 2: encodings[fan.index] = .fpe2
            case 4: encodings[fan.index] = .flt
            default: throw IntelFanControllerError.unsupportedTargetEncoding(fan.index)
            }
            let mode = try smc.read(SMCKey("F\(fan.index)Md"))
            guard mode == [0] else { throw IntelFanControllerError.unverifiedModeKey(fan.index) }
            ranges[fan.index] = minimum...maximum
            modes[fan.index] = mode
        }

        self.ranges = ranges
        self.encodings = encodings
        self.automaticModeValues = modes
    }

    public func setManual(fanIndex: Int, targetRPM: Double) throws {
        let validator = FanRequestValidator(ranges: ranges)
        try validator.validateManual(
            fanIndex: fanIndex,
            targetRPM: targetRPM,
            expiresAt: Date().addingTimeInterval(1),
            now: Date(),
            lastRequestAt: nil
        )
        guard let encoding = encodings[fanIndex] else { throw FanRequestValidationError.unknownFan(fanIndex) }
        let targetBytes: [UInt8]
        switch encoding {
        case .fpe2: targetBytes = try SMCValueCodec.encodeFPE2(targetRPM)
        case .flt: targetBytes = try SMCValueCodec.encodeFLT(targetRPM)
        }
        try smc.write(SMCKey("F\(fanIndex)Tg"), bytes: targetBytes)
        try smc.write(SMCKey("F\(fanIndex)Md"), bytes: [1])
    }

    public func restoreAutomatic(fanIndices: [Int]) throws {
        for index in Set(fanIndices).sorted() {
            guard let automaticValue = automaticModeValues[index] else {
                throw FanRequestValidationError.unknownFan(index)
            }
            try smc.write(SMCKey("F\(index)Md"), bytes: automaticValue)
        }
    }
}
