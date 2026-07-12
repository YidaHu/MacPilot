import XCTest
@testable import MacPilotCalendar

final class ReminderStoreTests: XCTestCase {
    private func temporaryURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacPilotCalendarTests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(UUID().uuidString).json")
    }

    func testMissingFileLoadsEmptyKeys() throws {
        XCTAssertEqual(try ReminderStore(fileURL: temporaryURL()).remindedKeys(), [])
    }

    func testMarkIsPersistentAndIdempotent() throws {
        let url = try temporaryURL()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let event = CalendarEventSnapshot(id: "event", startDate: date, isAllDay: false)
        let store = ReminderStore(fileURL: url)
        try store.markReminded(event: event, remindedAt: date.addingTimeInterval(-600))
        try store.markReminded(event: event, remindedAt: date.addingTimeInterval(-300))
        XCTAssertTrue(try ReminderStore(fileURL: url).hasReminded(event: event))
        XCTAssertEqual(try store.loadRecords().count, 1)
    }

    func testRecurringInstancesUseStartDateInKey() throws {
        let store = ReminderStore(fileURL: try temporaryURL())
        let first = CalendarEventSnapshot(id: "recurring", startDate: Date(timeIntervalSince1970: 1_800_000_000), isAllDay: false)
        let second = CalendarEventSnapshot(id: "recurring", startDate: first.startDate.addingTimeInterval(604_800), isAllDay: false)
        try store.markReminded(event: first, remindedAt: first.startDate)
        XCTAssertTrue(try store.hasReminded(event: first))
        XCTAssertFalse(try store.hasReminded(event: second))
    }
}
