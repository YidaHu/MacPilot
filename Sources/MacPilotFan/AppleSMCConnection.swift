import Foundation
import IOKit

public final class AppleSMCConnection: SMCKeyReading {
    private static let selector: UInt32 = 2
    private static let readBytesCommand: UInt8 = 5
    private static let readKeyInfoCommand: UInt8 = 9

    private var connection: io_connect_t = 0

    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCReadError.connectionFailed(KERN_NOT_FOUND) }
        defer { IOObjectRelease(service) }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == KERN_SUCCESS else {
            connection = 0
            throw SMCReadError.connectionFailed(result)
        }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    public func read(_ key: SMCKey) throws -> [UInt8] {
        var infoInput = SMCKeyData()
        infoInput.key = key.rawValue
        infoInput.data8 = Self.readKeyInfoCommand
        let infoOutput = try call(infoInput)

        let size = Int(infoOutput.keyInfo.dataSize)
        guard (1...32).contains(size) else { throw SMCReadError.malformedValue(key.stringValue) }

        var readInput = SMCKeyData()
        readInput.key = key.rawValue
        readInput.keyInfo.dataSize = infoOutput.keyInfo.dataSize
        readInput.data8 = Self.readBytesCommand
        let readOutput = try call(readInput)

        return withUnsafeBytes(of: readOutput.bytes) { Array($0.prefix(size)) }
    }

    private func call(_ input: SMCKeyData) throws -> SMCKeyData {
        var input = input
        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let result = withUnsafePointer(to: &input) { inputPointer in
            withUnsafeMutablePointer(to: &output) { outputPointer in
                IOConnectCallStructMethod(
                    connection,
                    Self.selector,
                    inputPointer,
                    MemoryLayout<SMCKeyData>.stride,
                    outputPointer,
                    &outputSize
                )
            }
        }
        guard result == KERN_SUCCESS else { throw SMCReadError.callFailed(result) }
        guard output.result == 0 else { throw SMCReadError.smcResult(output.result) }
        return output
    }
}

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
}

private struct SMCPowerLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPowerLimit: UInt32 = 0
    var gpuPowerLimit: UInt32 = 0
    var memoryPowerLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    var padding: (UInt8, UInt8, UInt8) = (0, 0, 0)
}

private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCKeyData {
    var key: UInt32 = 0
    var version = SMCVersion()
    var powerLimitData = SMCPowerLimitData()
    var padding0: UInt32 = 0
    var keyInfo = SMCKeyInfoData()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var padding1: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}

enum SMCABI {
    static let structureStride = MemoryLayout<SMCKeyData>.stride
    static let keyInfoOffset = MemoryLayout<SMCKeyData>.offset(of: \.keyInfo)!
    static let resultOffset = MemoryLayout<SMCKeyData>.offset(of: \.result)!
    static let commandOffset = MemoryLayout<SMCKeyData>.offset(of: \.data8)!
    static let data32Offset = MemoryLayout<SMCKeyData>.offset(of: \.data32)!
    static let bytesOffset = MemoryLayout<SMCKeyData>.offset(of: \.bytes)!
}
