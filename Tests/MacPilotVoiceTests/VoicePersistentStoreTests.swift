import XCTest
@testable import MacPilotVoice

final class VoicePersistentStoreTests: XCTestCase {
    func testSavedHistoryCanBeReadNewestFirst() async throws {
        let store = try VoicePersistentStore(inMemory: true)
        let older = VoiceHistoryEntry(createdAt: Date(timeIntervalSince1970: 1), rawText: "old", polishedText: "旧", duration: 1)
        let newer = VoiceHistoryEntry(createdAt: Date(timeIntervalSince1970: 2), rawText: "new", polishedText: "新", duration: 2)

        try await store.save(older)
        try await store.save(newer)

        XCTAssertEqual(try store.history(limit: 1), [newer])
    }
}
