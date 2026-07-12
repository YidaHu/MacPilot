import Foundation
import MacPilotFan

public protocol FanControlling: FanAutomaticRestoring {
    func setManual(fanIndex: Int, targetRPM: Double) throws
}

extension IntelFanController: FanControlling {}

public final class FanHelperService: NSObject, FanHelperProtocol {
    private let controller: any FanControlling
    private let validator: FanRequestValidator
    private let leaseManager: FanLeaseManager
    private let clock: () -> Date
    private let lock = NSRecursiveLock()
    private var lastRequestAt: Date?
    private var expiryTimer: DispatchSourceTimer?

    public init(
        controller: any FanControlling,
        validator: FanRequestValidator,
        clock: @escaping () -> Date = Date.init,
        startsExpiryTimer: Bool = true
    ) {
        self.controller = controller
        self.validator = validator
        self.leaseManager = FanLeaseManager(restorer: controller)
        self.clock = clock
        super.init()
        if startsExpiryTimer { startExpiryTimer() }
    }

    deinit {
        expiryTimer?.cancel()
        leaseManager.helperWillTerminate()
    }

    public var activeLeaseID: UUID? { leaseManager.activeLeaseID }

    public func setManual(
        fanIndex: Int,
        targetRPM: Double,
        leaseID: NSUUID,
        expiresAt: NSDate,
        withReply reply: @escaping (NSError?) -> Void
    ) {
        lock.withLock {
            let now = clock()
            do {
                try validator.validateManual(
                    fanIndex: fanIndex,
                    targetRPM: targetRPM,
                    expiresAt: expiresAt as Date,
                    now: now,
                    lastRequestAt: lastRequestAt
                )
                try controller.setManual(fanIndex: fanIndex, targetRPM: targetRPM)
                leaseManager.begin(leaseID: leaseID as UUID, fanIndex: fanIndex, expiresAt: expiresAt as Date)
                lastRequestAt = now
                reply(nil)
            } catch {
                reply(error as NSError)
            }
        }
    }

    public func renew(leaseID: NSUUID, expiresAt: NSDate, withReply reply: @escaping (NSError?) -> Void) {
        lock.withLock {
            do {
                try validator.validateLease(expiresAt: expiresAt as Date, now: clock())
                try leaseManager.renew(leaseID: leaseID as UUID, expiresAt: expiresAt as Date)
                reply(nil)
            } catch {
                reply(error as NSError)
            }
        }
    }

    public func restoreAutomatic(fanIndices: [NSNumber], withReply reply: @escaping (NSError?) -> Void) {
        lock.withLock {
            leaseManager.restoreAutomatic()
            if let description = leaseManager.lastRestoreErrorDescription {
                reply(NSError(domain: "com.huyida.macpilot.fanhelper", code: 2, userInfo: [NSLocalizedDescriptionKey: description]))
            } else {
                reply(nil)
            }
        }
    }

    public func status(withReply reply: @escaping ([String: Any]) -> Void) {
        var status: [String: Any] = ["manualActive": activeLeaseID != nil]
        if let id = activeLeaseID { status["leaseID"] = id.uuidString }
        if let error = leaseManager.lastRestoreErrorDescription { status["restoreError"] = error }
        reply(status)
    }

    public func connectionInvalidated() { leaseManager.connectionInvalidated() }
    public func helperWillTerminate() { leaseManager.helperWillTerminate() }

    private func startExpiryTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.leaseManager.expireIfNeeded(now: self.clock())
        }
        timer.resume()
        expiryTimer = timer
    }
}

private extension NSRecursiveLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
