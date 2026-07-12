import XCTest
@testable import MacPilotCalendar

final class ReminderSchedulerTests: XCTestCase {
    func testScanUsesFifteenMinuteWindowAndDeduplicates() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let event = CalendarEventSnapshot(id: "due", startDate: now.addingTimeInterval(600), isAllDay: false)
        let provider = FakeCalendarProvider(events: [event])
        let presenter = FakeRocketPresenter()
        let store = ReminderStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json"))
        let scheduler = ReminderScheduler(calendarProvider: provider, reminderStore: store, rocketPresenter: presenter, decisionEngine: .init())

        let first = try scheduler.scanOnce(now: now)
        let second = try scheduler.scanOnce(now: now.addingTimeInterval(30))

        XCTAssertEqual(provider.requestedEnd, now.addingTimeInterval(15 * 60 + 30))
        XCTAssertEqual(first.triggeredCount, 1)
        XCTAssertEqual(second.triggeredCount, 0)
        XCTAssertEqual(presenter.presentCount, 1)
    }
}

private final class FakeCalendarProvider: CalendarEventProviding {
    var requestedEnd: Date?
    let snapshotEvents: [CalendarEventSnapshot]
    init(events: [CalendarEventSnapshot]) { snapshotEvents = events }
    func events(from start: Date, to end: Date) throws -> [CalendarEventSnapshot] {
        requestedEnd = end
        return snapshotEvents
    }
}

private final class FakeRocketPresenter: RocketReminderPresenting {
    private(set) var presentCount = 0
    func presentRocket() { presentCount += 1 }
}
