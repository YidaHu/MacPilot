import XCTest
@testable import MacPilotFanHelper

final class FanLeaseManagerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testLeaseTimeoutRestoresExactlyOnce() throws {
        let restorer = RecordingRestorer()
        let manager = FanLeaseManager(restorer: restorer)
        manager.begin(leaseID: UUID(), fanIndex: 0, expiresAt: now.addingTimeInterval(2))
        manager.begin(leaseID: manager.activeLeaseID!, fanIndex: 1, expiresAt: now.addingTimeInterval(2))

        manager.expireIfNeeded(now: now.addingTimeInterval(3))
        manager.expireIfNeeded(now: now.addingTimeInterval(4))

        XCTAssertEqual(restorer.calls, [[0, 1]])
    }

    func testXPCInvalidationRestoresExactlyOnce() {
        assertSingleRestore { $0.connectionInvalidated() }
    }

    func testTerminationRestoresExactlyOnce() {
        assertSingleRestore { $0.helperWillTerminate() }
    }

    func testExplicitAutomaticRestoresExactlyOnce() {
        assertSingleRestore { $0.restoreAutomatic() }
    }

    func testRenewExtendsMatchingLeaseOnly() throws {
        let restorer = RecordingRestorer()
        let manager = FanLeaseManager(restorer: restorer)
        let leaseID = UUID()
        manager.begin(leaseID: leaseID, fanIndex: 0, expiresAt: now.addingTimeInterval(2))

        XCTAssertThrowsError(try manager.renew(leaseID: UUID(), expiresAt: now.addingTimeInterval(5)))
        XCTAssertNoThrow(try manager.renew(leaseID: leaseID, expiresAt: now.addingTimeInterval(5)))
        manager.expireIfNeeded(now: now.addingTimeInterval(3))
        XCTAssertTrue(restorer.calls.isEmpty)
    }

    private func assertSingleRestore(trigger: (FanLeaseManager) -> Void) {
        let restorer = RecordingRestorer()
        let manager = FanLeaseManager(restorer: restorer)
        manager.begin(leaseID: UUID(), fanIndex: 0, expiresAt: now.addingTimeInterval(2))
        trigger(manager)
        trigger(manager)
        XCTAssertEqual(restorer.calls, [[0]])
    }
}

private final class RecordingRestorer: FanAutomaticRestoring {
    var calls: [[Int]] = []
    func restoreAutomatic(fanIndices: [Int]) throws { calls.append(fanIndices) }
}
