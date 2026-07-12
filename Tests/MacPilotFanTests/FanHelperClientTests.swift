import XCTest
@testable import MacPilotFan

final class FanHelperClientTests: XCTestCase {
    func testConnectionProviderIsCreatedLazilyOnFirstRequest() async throws {
        let remote = RemoteSpy()
        var factoryCalls = 0
        let client = FanHelperClient(remoteProviderFactory: {
            factoryCalls += 1
            return { _ in remote }
        })

        XCTAssertEqual(factoryCalls, 0)
        try await client.setManual(fanIndex: 0, targetRPM: 3_000, leaseID: UUID(), expiresAt: Date().addingTimeInterval(3))
        XCTAssertEqual(factoryCalls, 1)
    }

    func testManualRequestForwardsClosedContractParameters() async throws {
        let remote = RemoteSpy()
        let client = FanHelperClient(remoteProvider: { _ in remote })
        let leaseID = UUID()
        let expiry = Date(timeIntervalSince1970: 3_000)

        try await client.setManual(fanIndex: 1, targetRPM: 3_200, leaseID: leaseID, expiresAt: expiry)

        XCTAssertEqual(remote.manualFanIndex, 1)
        XCTAssertEqual(remote.manualTargetRPM, 3_200)
        XCTAssertEqual(remote.manualLeaseID as UUID?, leaseID)
        XCTAssertEqual(remote.manualExpiry as Date?, expiry)
    }

    func testHelperErrorIsPropagated() async {
        let remote = RemoteSpy()
        remote.replyError = NSError(domain: "test", code: 42)
        let client = FanHelperClient(remoteProvider: { _ in remote })

        do {
            try await client.setManual(fanIndex: 0, targetRPM: 3_000, leaseID: UUID(), expiresAt: Date().addingTimeInterval(3))
            XCTFail("Expected helper error")
        } catch {
            XCTAssertEqual((error as NSError).code, 42)
        }
    }
}

private final class RemoteSpy: NSObject, FanHelperProtocol {
    var replyError: NSError?
    var manualFanIndex: Int?
    var manualTargetRPM: Double?
    var manualLeaseID: NSUUID?
    var manualExpiry: NSDate?

    func setManual(fanIndex: Int, targetRPM: Double, leaseID: NSUUID, expiresAt: NSDate, withReply reply: @escaping (NSError?) -> Void) {
        manualFanIndex = fanIndex
        manualTargetRPM = targetRPM
        manualLeaseID = leaseID
        manualExpiry = expiresAt
        reply(replyError)
    }

    func renew(leaseID: NSUUID, expiresAt: NSDate, withReply reply: @escaping (NSError?) -> Void) { reply(replyError) }
    func restoreAutomatic(fanIndices: [NSNumber], withReply reply: @escaping (NSError?) -> Void) { reply(replyError) }
    func status(withReply reply: @escaping ([String: Any]) -> Void) { reply([:]) }
}
