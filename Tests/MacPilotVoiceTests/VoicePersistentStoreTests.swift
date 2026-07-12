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

    func testHistoryCanBeUpdatedAndDeletedByID() async throws {
        let store = try VoicePersistentStore(inMemory: true)
        let entry = VoiceHistoryEntry(rawText: "raw", polishedText: "first", duration: 1)
        try await store.save(entry)

        try store.updateHistory(id: entry.id, polishedText: "second")
        XCTAssertEqual(try store.history(limit: 10).first?.polishedText, "second")

        try store.deleteHistory(id: entry.id)
        XCTAssertTrue(try store.history(limit: 10).isEmpty)
    }
}
