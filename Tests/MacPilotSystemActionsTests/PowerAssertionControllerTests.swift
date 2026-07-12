import XCTest
@testable import MacPilotSystemActions

final class PowerAssertionControllerTests: XCTestCase {
    func testDisableReleasesExactAssertionCreatedForKind() async throws {
        let api = FakePowerAssertionAPI(ids: [42])
        let controller = PowerAssertionController(api: api)

        try await controller.enable(.system, reason: "test")
        await controller.disable(.system)
        let released = await api.releasedIDs()
        let enabled = await controller.isEnabled(.system)

        XCTAssertEqual(released, [42])
        XCTAssertFalse(enabled)
    }

    func testDisableIsIdempotent() async throws {
        let api = FakePowerAssertionAPI(ids: [7])
        let controller = PowerAssertionController(api: api)

        try await controller.enable(.display, reason: "test")
        await controller.disable(.display)
        await controller.disable(.display)
        let released = await api.releasedIDs()

        XCTAssertEqual(released, [7])
    }

    func testReplacingAssertionReleasesPreviousID() async throws {
        let api = FakePowerAssertionAPI(ids: [10, 11])
        let controller = PowerAssertionController(api: api)

        try await controller.enable(.system, reason: "first")
        try await controller.enable(.system, reason: "second")
        let released = await api.releasedIDs()
        let enabled = await controller.isEnabled(.system)

        XCTAssertEqual(released, [10])
        XCTAssertTrue(enabled)
    }
}

private actor FakePowerAssertionAPI: PowerAssertionAPI {
    private var ids: [UInt32]
    private var released: [UInt32] = []

    init(ids: [UInt32]) { self.ids = ids }

    func create(kind: PowerAssertionKind, reason: String) async throws -> UInt32 {
        ids.removeFirst()
    }

    func release(id: UInt32) async {
        released.append(id)
    }

    func releasedIDs() -> [UInt32] { released }
}
