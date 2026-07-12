import Foundation

public protocol CalendarEventProviding {
    func events(from start: Date, to end: Date) throws -> [CalendarEventSnapshot]
}

public protocol RocketReminderPresenting {
    func presentRocket()
}

public final class ReminderScheduler {
    public struct ScanResult: Equatable {
        public let scannedCount: Int
        public let triggeredCount: Int
    }

    private let calendarProvider: any CalendarEventProviding
    private let reminderStore: ReminderStore
    private let rocketPresenter: any RocketReminderPresenting
    private let decisionEngine: ReminderDecisionEngine

    public init(calendarProvider: any CalendarEventProviding, reminderStore: ReminderStore, rocketPresenter: any RocketReminderPresenting, decisionEngine: ReminderDecisionEngine) {
        self.calendarProvider = calendarProvider
        self.reminderStore = reminderStore
        self.rocketPresenter = rocketPresenter
        self.decisionEngine = decisionEngine
    }

    @discardableResult
    public func scanOnce(now: Date) throws -> ScanResult {
        let events = try calendarProvider.events(from: now, to: now.addingTimeInterval(decisionEngine.scanHorizon))
        let due = decisionEngine.eventsNeedingReminder(from: events, now: now, remindedKeys: try reminderStore.remindedKeys())
        for event in due {
            try reminderStore.markReminded(event: event, remindedAt: now)
            rocketPresenter.presentRocket()
        }
        return ScanResult(scannedCount: events.count, triggeredCount: due.count)
    }
}
