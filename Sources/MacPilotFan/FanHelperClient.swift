import Foundation

public enum FanHelperClientError: Error, Equatable {
    case unavailable
}

public final class FanHelperClient {
    typealias RemoteProvider = (@escaping (Error) -> Void) -> FanHelperProtocol?

    private let connection: NSXPCConnection?
    private let remoteProvider: RemoteProvider

    public init() {
        let connection = NSXPCConnection(machServiceName: "com.huyida.macpilot.fanhelper", options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.resume()
        self.connection = connection
        self.remoteProvider = { errorHandler in
            connection.remoteObjectProxyWithErrorHandler(errorHandler) as? FanHelperProtocol
        }
    }

    init(remoteProvider: @escaping RemoteProvider) {
        self.connection = nil
        self.remoteProvider = remoteProvider
    }

    deinit { connection?.invalidate() }

    public func setManual(fanIndex: Int, targetRPM: Double, leaseID: UUID, expiresAt: Date) async throws {
        try await perform { remote, reply in
            remote.setManual(
                fanIndex: fanIndex,
                targetRPM: targetRPM,
                leaseID: leaseID as NSUUID,
                expiresAt: expiresAt as NSDate,
                withReply: reply
            )
        }
    }

    public func renew(leaseID: UUID, expiresAt: Date) async throws {
        try await perform { remote, reply in
            remote.renew(leaseID: leaseID as NSUUID, expiresAt: expiresAt as NSDate, withReply: reply)
        }
    }

    public func restoreAutomatic(fanIndices: [Int]) async throws {
        try await perform { remote, reply in
            remote.restoreAutomatic(fanIndices: fanIndices.map(NSNumber.init(value:)), withReply: reply)
        }
    }

    private func perform(_ operation: @escaping (FanHelperProtocol, @escaping (NSError?) -> Void) -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ContinuationGate(continuation)
            guard let remote = remoteProvider({ gate.resume(throwing: $0) }) else {
                gate.resume(throwing: FanHelperClientError.unavailable)
                return
            }
            operation(remote) { error in
                if let error { gate.resume(throwing: error) }
                else { gate.resume() }
            }
        }
    }
}

private final class ContinuationGate {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resume() { complete { $0.resume() } }
    func resume(throwing error: Error) { complete { $0.resume(throwing: error) } }

    private func complete(_ body: (CheckedContinuation<Void, Error>) -> Void) {
        lock.lock()
        guard let continuation else { lock.unlock(); return }
        self.continuation = nil
        lock.unlock()
        body(continuation)
    }
}
