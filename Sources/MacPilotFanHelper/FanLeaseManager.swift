import Foundation

public protocol FanAutomaticRestoring: AnyObject {
    func restoreAutomatic(fanIndices: [Int]) throws
}

public enum FanLeaseError: Error, Equatable {
    case noActiveLease
    case leaseMismatch
}

public final class FanLeaseManager {
    private let restorer: any FanAutomaticRestoring
    private let lock = NSRecursiveLock()
    private var leaseID: UUID?
    private var expiresAt: Date?
    private var fanIndices = Set<Int>()
    public private(set) var lastRestoreErrorDescription: String?

    public init(restorer: any FanAutomaticRestoring) {
        self.restorer = restorer
    }

    public var activeLeaseID: UUID? {
        lock.withLock { leaseID }
    }

    public func begin(leaseID: UUID, fanIndex: Int, expiresAt: Date) {
        lock.withLock {
            if let current = self.leaseID, current != leaseID { restoreOnce() }
            self.leaseID = leaseID
            self.expiresAt = expiresAt
            fanIndices.insert(fanIndex)
        }
    }

    public func renew(leaseID: UUID, expiresAt: Date) throws {
        try lock.withLock {
            guard let current = self.leaseID else { throw FanLeaseError.noActiveLease }
            guard current == leaseID else { throw FanLeaseError.leaseMismatch }
            self.expiresAt = expiresAt
        }
    }

    public func expireIfNeeded(now: Date) {
        lock.withLock {
            guard let expiresAt, now >= expiresAt else { return }
            restoreOnce()
        }
    }

    public func connectionInvalidated() { lock.withLock { restoreOnce() } }
    public func helperWillTerminate() { lock.withLock { restoreOnce() } }
    public func restoreAutomatic() { lock.withLock { restoreOnce() } }

    private func restoreOnce() {
        guard leaseID != nil else { return }
        let indices = fanIndices.sorted()
        leaseID = nil
        expiresAt = nil
        fanIndices.removeAll()
        do {
            try restorer.restoreAutomatic(fanIndices: indices)
            lastRestoreErrorDescription = nil
        } catch {
            lastRestoreErrorDescription = String(describing: error)
        }
    }
}

private extension NSRecursiveLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
