import Foundation

public struct CalendarEventSnapshot: Equatable, Hashable {
    public let id: String
    public let startDate: Date
    public let isAllDay: Bool

    public init(id: String, startDate: Date, isAllDay: Bool) {
        self.id = id
        self.startDate = startDate
        self.isAllDay = isAllDay
    }

    public var reminderKey: ReminderKey { ReminderKey(eventID: id, startDate: startDate) }
}

public struct ReminderKey: Codable, Equatable, Hashable {
    public let eventID: String
    public let startDate: Date

    public init(eventID: String, startDate: Date) {
        self.eventID = eventID
        self.startDate = startDate
    }
}
