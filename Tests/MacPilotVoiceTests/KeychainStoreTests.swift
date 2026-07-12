import XCTest
@testable import MacPilotVoice

final class KeychainStoreTests: XCTestCase {
    func testRoundTripAndDeleteSecret() throws {
        let service = "com.huyida.macpilot.voice.tests.\(UUID().uuidString)"
        let store = KeychainStore(service: service)
        defer { try? store.delete(account: "stt-key") }

        try store.set("super-secret", account: "stt-key")
        XCTAssertEqual(try store.string(account: "stt-key"), "super-secret")
        try store.delete(account: "stt-key")
        XCTAssertNil(try store.string(account: "stt-key"))
    }
}
