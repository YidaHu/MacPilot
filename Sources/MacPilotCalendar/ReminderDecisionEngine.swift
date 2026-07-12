import Foundation

public struct ReminderDecisionEngine {
    public let leadTime: TimeInterval
    public let scanHorizon: TimeInterval
    public let startedGrace: TimeInterval

    public init(
        leadTime: TimeInterval = 10 * 60,
        scanHorizon: TimeInterval = 15 * 60,
        startedGrace: TimeInterval = 60
    ) {
        self.leadTime = leadTime
        self.scanHorizon = scanHorizon
        self.startedGrace = startedGrace
    }

    public func shouldTrigger(event: CalendarEventSnapshot, now: Date, remindedKeys: Set<ReminderKey>) -> Bool {
        guard !event.isAllDay, !remindedKeys.contains(event.reminderKey) else { return false }
        let seconds = event.startDate.timeIntervalSince(now)
        return (seconds >= 0 && seconds <= leadTime) || (seconds < 0 && abs(seconds) <= startedGrace)
    }

    public func eventsNeedingReminder(from events: [CalendarEventSnapshot], now: Date, remindedKeys: Set<ReminderKey>) -> [CalendarEventSnapshot] {
        events.filter { shouldTrigger(event: $0, now: now, remindedKeys: remindedKeys) }
    }
}
