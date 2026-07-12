import XCTest
@testable import MacPilotCalendar

final class ReminderDecisionEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testTriggersTenMinutesBeforeButIgnoresAllDayEvent() {
        let engine = ReminderDecisionEngine()
        let meeting = CalendarEventSnapshot(id: "meeting", startDate: now.addingTimeInterval(600), isAllDay: false)
        let allDay = CalendarEventSnapshot(id: "holiday", startDate: now.addingTimeInterval(600), isAllDay: true)
        XCTAssertTrue(engine.shouldTrigger(event: meeting, now: now, remindedKeys: []))
        XCTAssertFalse(engine.shouldTrigger(event: allDay, now: now, remindedKeys: []))
    }

    func testCatchUpEndsOneMinuteAfterStart() {
        let engine = ReminderDecisionEngine()
        let within = CalendarEventSnapshot(id: "within", startDate: now.addingTimeInterval(-45), isAllDay: false)
        let expired = CalendarEventSnapshot(id: "expired", startDate: now.addingTimeInterval(-90), isAllDay: false)
        XCTAssertTrue(engine.shouldTrigger(event: within, now: now, remindedKeys: []))
        XCTAssertFalse(engine.shouldTrigger(event: expired, now: now, remindedKeys: []))
    }

    func testAlreadyRemindedEventIsSkipped() {
        let event = CalendarEventSnapshot(id: "weekly", startDate: now.addingTimeInterval(600), isAllDay: false)
        XCTAssertFalse(ReminderDecisionEngine().shouldTrigger(event: event, now: now, remindedKeys: [event.reminderKey]))
    }
}
