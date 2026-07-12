import EventKit
import Foundation

public final class EventKitCalendarMonitor: CalendarAuthorizationProviding, CalendarEventProviding {
    private let eventStore: EKEventStore
    public init(eventStore: EKEventStore = EKEventStore()) { self.eventStore = eventStore }

    public var state: CalendarAuthorizationState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .authorized
        @unknown default: return .unknown
        }
    }

    public func requestAccess(completion: @escaping (Bool) -> Void) {
        eventStore.requestAccess(to: .event) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    public func events(from start: Date, to end: Date) throws -> [CalendarEventSnapshot] {
        guard state == .authorized else { throw CalendarMonitorError.accessDenied }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        return eventStore.events(matching: predicate).compactMap { event in
            guard let identifier = event.eventIdentifier else { return nil }
            return CalendarEventSnapshot(id: identifier, startDate: event.startDate, isAllDay: event.isAllDay)
        }
    }
}

public enum CalendarMonitorError: LocalizedError {
    case accessDenied
    public var errorDescription: String? { "MacPilot 没有日历读取权限" }
}
