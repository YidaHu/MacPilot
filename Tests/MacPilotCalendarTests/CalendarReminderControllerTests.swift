import XCTest
@testable import MacPilotCalendar

@MainActor
final class CalendarReminderControllerTests: XCTestCase {
    func testEnablingStartsOneScheduleAndDisablingCancelsIt() {
        let timer = FakeTimerScheduler()
        let controller = CalendarReminderController(
            initiallyEnabled: false,
            authorization: FakeAuthorization(state: .authorized),
            scanner: FakeScanner(),
            timerScheduler: timer
        )

        controller.setEnabled(true)
        controller.setEnabled(true)
        XCTAssertEqual(timer.scheduledIntervals, [45])
        XCTAssertEqual(controller.status, .active)

        controller.setEnabled(false)
        XCTAssertTrue(timer.token.isCancelled)
        XCTAssertEqual(controller.status, .disabled)
    }

    func testDeniedPermissionWaitsWithoutScheduling() {
        let timer = FakeTimerScheduler()
        let controller = CalendarReminderController(
            initiallyEnabled: false,
            authorization: FakeAuthorization(state: .denied),
            scanner: FakeScanner(),
            timerScheduler: timer
        )

        controller.setEnabled(true)

        XCTAssertEqual(controller.status, .waitingForPermission)
        XCTAssertEqual(timer.scheduledIntervals, [])
    }

    func testWakeScansOnlyWhileEnabled() {
        let scanner = FakeScanner()
        let controller = CalendarReminderController(
            initiallyEnabled: false,
            authorization: FakeAuthorization(state: .authorized),
            scanner: scanner,
            timerScheduler: FakeTimerScheduler()
        )

        controller.handleWake()
        XCTAssertEqual(scanner.scanCount, 0)
        controller.setEnabled(true)
        let afterEnable = scanner.scanCount
        controller.handleWake()
        XCTAssertEqual(scanner.scanCount, afterEnable + 1)
    }
}

private final class FakeAuthorization: CalendarAuthorizationProviding {
    var state: CalendarAuthorizationState
    init(state: CalendarAuthorizationState) { self.state = state }
    func requestAccess(completion: @escaping (Bool) -> Void) { completion(state == .authorized) }
}

private final class FakeScanner: ReminderScanning {
    private(set) var scanCount = 0
    func scan(now: Date) throws { scanCount += 1 }
}

private final class FakeTimerToken: ReminderTimerToken {
    private(set) var isCancelled = false
    func cancel() { isCancelled = true }
}

private final class FakeTimerScheduler: ReminderTimerScheduling {
    let token = FakeTimerToken()
    private(set) var scheduledIntervals: [TimeInterval] = []
    func schedule(every interval: TimeInterval, action: @escaping () -> Void) -> any ReminderTimerToken {
        scheduledIntervals.append(interval)
        return token
    }
}
