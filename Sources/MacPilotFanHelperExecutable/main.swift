import Foundation
import MacPilotFan
import MacPilotFanHelper
import Security

private let machServiceName = "com.huyida.macpilot.fanhelper"

do {
    let smc = try AppleSMCConnection()
    let snapshot = try IntelFanReader(reader: smc).readSnapshot()
    let ranges = Dictionary(uniqueKeysWithValues: snapshot.fans.compactMap { fan -> (Int, ClosedRange<Double>)? in
        guard let minimum = fan.minimumRPM, let maximum = fan.maximumRPM, minimum < maximum else { return nil }
        return (fan.index, minimum...maximum)
    })
    guard ranges.count == snapshot.fans.count else { throw HelperStartupError.unverifiedRanges }

    let controller = try IntelFanController(smc: smc)
    let service = FanHelperService(controller: controller, validator: FanRequestValidator(ranges: ranges))
    let requirement = Bundle.main.object(forInfoDictionaryKey: "MacPilotClientRequirement") as? String ?? ""
    let delegate = FanHelperListenerDelegate(service: service, requirement: requirement)
    let listener = NSXPCListener(machServiceName: machServiceName)
    listener.delegate = delegate
    listener.resume()
    RunLoop.current.run()
} catch {
    fputs("MacPilotFanHelper startup failed: \(error)\n", stderr)
    exit(1)
}

private enum HelperStartupError: Error { case unverifiedRanges }

private final class FanHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: FanHelperService
    private let requirement: String

    init(service: FanHelperService, requirement: String) {
        self.service = service
        self.requirement = requirement
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard ClientSignatureValidator(requirement: requirement).accepts(processIdentifier: connection.processIdentifier) else {
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.exportedObject = service
        connection.invalidationHandler = { [weak service] in service?.connectionInvalidated() }
        connection.interruptionHandler = { [weak service] in service?.connectionInvalidated() }
        connection.resume()
        return true
    }
}

private struct ClientSignatureValidator {
    let requirement: String

    func accepts(processIdentifier: pid_t) -> Bool {
        guard !requirement.isEmpty else { return false }
        let attributes = [kSecGuestAttributePid as String: processIdentifier] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &code) == errSecSuccess, let code else {
            return false
        }
        var secRequirement: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, SecCSFlags(), &secRequirement) == errSecSuccess,
              let secRequirement else { return false }
        return SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), secRequirement) == errSecSuccess
    }
}
