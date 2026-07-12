import Foundation
import IOKit.pwr_mgt

public enum PowerAssertionKind: Hashable, Sendable {
    case system
    case display
}

public enum PowerAssertionError: Error {
    case creationFailed(IOReturn)
}

public protocol PowerAssertionAPI: Sendable {
    func create(kind: PowerAssertionKind, reason: String) async throws -> UInt32
    func release(id: UInt32) async
}

public struct LivePowerAssertionAPI: PowerAssertionAPI {
    public init() {}

    public func create(kind: PowerAssertionKind, reason: String) async throws -> UInt32 {
        let assertionType: CFString = kind == .system
            ? kIOPMAssertionTypeNoIdleSleep as CFString
            : kIOPMAssertionTypeNoDisplaySleep as CFString
        var identifier: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            assertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &identifier
        )
        guard result == kIOReturnSuccess else {
            throw PowerAssertionError.creationFailed(result)
        }
        return identifier
    }

    public func release(id: UInt32) async {
        IOPMAssertionRelease(IOPMAssertionID(id))
    }
}

public actor PowerAssertionController {
    private let api: any PowerAssertionAPI
    private var identifiers: [PowerAssertionKind: UInt32] = [:]
    private var expiryTasks: [PowerAssertionKind: Task<Void, Never>] = [:]

    public init(api: any PowerAssertionAPI = LivePowerAssertionAPI()) {
        self.api = api
    }

    public func enable(
        _ kind: PowerAssertionKind,
        reason: String,
        duration: TimeInterval? = nil
    ) async throws {
        await disable(kind)
        let identifier = try await api.create(kind: kind, reason: reason)
        identifiers[kind] = identifier
        if let duration, duration > 0 {
            expiryTasks[kind] = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                    await self?.disable(kind)
                } catch {}
            }
        }
    }

    public func disable(_ kind: PowerAssertionKind) async {
        expiryTasks.removeValue(forKey: kind)?.cancel()
        guard let identifier = identifiers.removeValue(forKey: kind) else { return }
        await api.release(id: identifier)
    }

    public func disableAll() async {
        for kind in Array(identifiers.keys) {
            await disable(kind)
        }
    }

    public func isEnabled(_ kind: PowerAssertionKind) -> Bool {
        identifiers[kind] != nil
    }
}
