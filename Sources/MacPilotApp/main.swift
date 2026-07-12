import AppKit
import MacPilotCalendar
import MacPilotCore
import MacPilotFan
import MacPilotMetrics
import MacPilotSystemActions

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: AppStore?
    private var menuBarController: MenuBarController?
    private var settingsWindowController: SettingsWindowController?
    private var calendarController: CalendarReminderController?
    private var rocketOverlay: RocketOverlayWindow?
    private var fanStore: FanStore?
    private var toolsStore: SystemToolsStore?
    private var cleaningController: CleaningOverlayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.setUpApplication()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.menuBarController?.stopRefreshing()
            self?.cleaningController?.stop()
            await self?.toolsStore?.shutdown()
        }
    }

    @MainActor
    private func setUpApplication() {
        _ = NSApp.setActivationPolicy(.accessory)
        let store = AppStore(metrics: LiveMetricsProvider())
        let fans = FanStore.live()
        fans.refresh()
        let tools = SystemToolsStore()
        let cleaning = CleaningOverlayController()
        let monitor = EventKitCalendarMonitor()
        let rocket = RocketOverlayWindow()
        let reminderStoreURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacPilot", isDirectory: true)
            .appendingPathComponent("calendar-reminders.json")
        let scheduler = ReminderScheduler(
            calendarProvider: monitor,
            reminderStore: ReminderStore(fileURL: reminderStoreURL),
            rocketPresenter: rocket,
            decisionEngine: ReminderDecisionEngine()
        )
        let calendar = CalendarReminderController(
            initiallyEnabled: UserDefaults.standard.bool(forKey: "rocketReminderEnabled"),
            authorization: monitor,
            scanner: scheduler,
            testAction: { rocket.presentRocket() },
            enabledDidChange: { UserDefaults.standard.set($0, forKey: "rocketReminderEnabled") }
        )
        let settings = SettingsWindowController(calendar: calendar, fans: fans, tools: tools)
        let menuBar = MenuBarController(store: store, calendar: calendar, fans: fans, tools: tools, cleaning: cleaning) {
            settings.show()
        }
        self.store = store
        settingsWindowController = settings
        menuBarController = menuBar
        calendarController = calendar
        rocketOverlay = rocket
        fanStore = fans
        toolsStore = tools
        cleaningController = cleaning
        menuBar.startRefreshing()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleWake() {
        Task { @MainActor [weak self] in self?.calendarController?.handleWake() }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
