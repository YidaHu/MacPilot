import AppKit
import MacPilotCore
import MacPilotMetrics

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: AppStore?
    private var menuBarController: MenuBarController?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.setUpApplication()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.menuBarController?.stopRefreshing()
        }
    }

    @MainActor
    private func setUpApplication() {
        _ = NSApp.setActivationPolicy(.accessory)
        let store = AppStore(metrics: LiveMetricsProvider())
        let settings = SettingsWindowController()
        let menuBar = MenuBarController(store: store) {
            settings.show()
        }
        self.store = store
        settingsWindowController = settings
        menuBarController = menuBar
        menuBar.startRefreshing()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
