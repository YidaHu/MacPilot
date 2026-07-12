import Combine
import Foundation

public enum CalendarAuthorizationState: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unknown
}

public enum CalendarReminderStatus: Equatable {
    case disabled
    case active
    case waitingForPermission
    case failed(String)
}

public protocol CalendarAuthorizationProviding: AnyObject {
    var state: CalendarAuthorizationState { get }
    func requestAccess(completion: @escaping (Bool) -> Void)
}

public protocol ReminderScanning: AnyObject {
    func scan(now: Date) throws
}

extension ReminderScheduler: ReminderScanning {
    public func scan(now: Date) throws { _ = try scanOnce(now: now) }
}

public protocol ReminderTimerToken: AnyObject {
    func cancel()
}

public protocol ReminderTimerScheduling: AnyObject {
    func schedule(every interval: TimeInterval, action: @escaping () -> Void) -> any ReminderTimerToken
}

private final class FoundationTimerToken: ReminderTimerToken {
    private let timer: Timer
    init(timer: Timer) { self.timer = timer }
    func cancel() { timer.invalidate() }
}

public final class FoundationReminderTimerScheduler: ReminderTimerScheduling {
    public init() {}
    public func schedule(every interval: TimeInterval, action: @escaping () -> Void) -> any ReminderTimerToken {
        FoundationTimerToken(timer: Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in action() })
    }
}

@MainActor
public final class CalendarReminderController: ObservableObject {
    @Published public private(set) var isEnabled: Bool
    @Published public private(set) var status: CalendarReminderStatus

    private let authorization: any CalendarAuthorizationProviding
    private let scanner: any ReminderScanning
    private let timerScheduler: any ReminderTimerScheduling
    private let testAction: () -> Void
    private let enabledDidChange: (Bool) -> Void
    private var timerToken: (any ReminderTimerToken)?

    public init(
        initiallyEnabled: Bool,
        authorization: any CalendarAuthorizationProviding,
        scanner: any ReminderScanning,
        timerScheduler: any ReminderTimerScheduling = FoundationReminderTimerScheduler(),
        testAction: @escaping () -> Void = {},
        enabledDidChange: @escaping (Bool) -> Void = { _ in }
    ) {
        isEnabled = initiallyEnabled
        status = initiallyEnabled ? .waitingForPermission : .disabled
        self.authorization = authorization
        self.scanner = scanner
        self.timerScheduler = timerScheduler
        self.testAction = testAction
        self.enabledDidChange = enabledDidChange
        if initiallyEnabled { activateIfAuthorized() }
    }

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled || (enabled && timerToken == nil) else { return }
        isEnabled = enabled
        enabledDidChange(enabled)
        if enabled {
            activateIfAuthorized()
        } else {
            timerToken?.cancel()
            timerToken = nil
            status = .disabled
        }
    }

    public func handleWake() {
        guard isEnabled, authorization.state == .authorized else { return }
        scanNow()
    }

    public func testReminder() {
        testAction()
    }

    private func activateIfAuthorized() {
        switch authorization.state {
        case .authorized:
            startScanning()
        case .notDetermined:
            status = .waitingForPermission
            authorization.requestAccess { [weak self] granted in
                Task { @MainActor in
                    guard let self, self.isEnabled else { return }
                    granted ? self.startScanning() : (self.status = .waitingForPermission)
                }
            }
        case .denied, .restricted, .unknown:
            status = .waitingForPermission
        }
    }

    private func startScanning() {
        guard timerToken == nil else { return }
        status = .active
        scanNow()
        timerToken = timerScheduler.schedule(every: 45) { [weak self] in
            Task { @MainActor in self?.scanNow() }
        }
    }

    private func scanNow() {
        do {
            try scanner.scan(now: Date())
            if isEnabled { status = .active }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
