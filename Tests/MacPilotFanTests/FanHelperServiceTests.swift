import XCTest
@testable import MacPilotFan
@testable import MacPilotFanHelper

final class FanHelperServiceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000)

    func testValidManualRequestWritesAndStartsLease() {
        let controller = ServiceControllerSpy()
        let service = makeService(controller: controller)
        var replyError: NSError?

        service.setManual(
            fanIndex: 0,
            targetRPM: 3_000,
            leaseID: NSUUID(uuidString: "C69C1C0B-126E-4B42-B926-05D022F9F571")!,
            expiresAt: now.addingTimeInterval(3) as NSDate
        ) { replyError = $0 }

        XCTAssertNil(replyError)
        XCTAssertEqual(controller.manualCalls, [.init(index: 0, rpm: 3_000)])
        XCTAssertNotNil(service.activeLeaseID)
    }

    func testInvalidManualRequestNeverReachesController() {
        let controller = ServiceControllerSpy()
        let service = makeService(controller: controller)
        var replyError: NSError?

        service.setManual(
            fanIndex: 0,
            targetRPM: 10_000,
            leaseID: NSUUID(),
            expiresAt: now.addingTimeInterval(3) as NSDate
        ) { replyError = $0 }

        XCTAssertNotNil(replyError)
        XCTAssertTrue(controller.manualCalls.isEmpty)
    }

    func testConnectionInvalidationRestoresActiveFan() {
        let controller = ServiceControllerSpy()
        let service = makeService(controller: controller)
        service.setManual(fanIndex: 0, targetRPM: 3_000, leaseID: NSUUID(), expiresAt: now.addingTimeInterval(3) as NSDate) { _ in }

        service.connectionInvalidated()

        XCTAssertEqual(controller.restoreCalls, [[0]])
    }

    private func makeService(controller: ServiceControllerSpy) -> FanHelperService {
        FanHelperService(
            controller: controller,
            validator: FanRequestValidator(ranges: [0: 1_200...5_900]),
            clock: { self.now },
            startsExpiryTimer: false
        )
    }
}

private struct ManualCall: Equatable {
    let index: Int
    let rpm: Double
}

private final class ServiceControllerSpy: FanControlling {
    var manualCalls: [ManualCall] = []
    var restoreCalls: [[Int]] = []

    func setManual(fanIndex: Int, targetRPM: Double) throws {
        manualCalls.append(.init(index: fanIndex, rpm: targetRPM))
    }

    func restoreAutomatic(fanIndices: [Int]) throws {
        restoreCalls.append(fanIndices)
    }
}
