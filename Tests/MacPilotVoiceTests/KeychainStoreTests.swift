import XCTest
import Security
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

    func testUpdatingSecretPreservesKeychainItemIdentity() throws {
        let service = "com.huyida.macpilot.voice.tests.\(UUID().uuidString)"
        let account = "llm-key"
        let store = KeychainStore(service: service)
        defer { try? store.delete(account: account) }

        try store.set("first-value", account: account)
        let originalReference = try persistentReference(service: service, account: account)
        let originalCreationDate = try creationDate(service: service, account: account)
        Thread.sleep(forTimeInterval: 1.1)

        try store.set("replacement-value", account: account)

        XCTAssertEqual(try store.string(account: account), "replacement-value")
        XCTAssertEqual(try persistentReference(service: service, account: account), originalReference)
        XCTAssertEqual(try creationDate(service: service, account: account), originalCreationDate)
    }

    private func persistentReference(service: String, account: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnPersistentRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainStoreError.status(status)
        }
        return data
    }

    private func creationDate(service: String, account: String) throws -> Date {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard
            status == errSecSuccess,
            let attributes = result as? [String: Any],
            let date = attributes[kSecAttrCreationDate as String] as? Date
        else {
            throw KeychainStoreError.status(status)
        }
        return date
    }
}
