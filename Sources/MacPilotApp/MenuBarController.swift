import AppKit
import MacPilotCore
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let store: AppStore
    private let openSettings: () -> Void
    private var refreshTask: Task<Void, Never>?

    init(store: AppStore, openSettings: @escaping () -> Void) {
        self.store = store
        self.openSettings = openSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: "MacPilot")
                ?? NSImage(systemSymbolName: "gauge", accessibilityDescription: "MacPilot")
            button.target = self
            button.action = #selector(togglePopover)
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 430, height: 660)
        popover.contentViewController = NSHostingController(
            rootView: RootPanelView(store: store, openSettings: openSettings)
        )
    }

    func startRefreshing() {
        scheduleRefresh(panelIsVisible: false)
    }

    func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            scheduleRefresh(panelIsVisible: true)
        }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.scheduleRefresh(panelIsVisible: false)
        }
    }

    private func scheduleRefresh(panelIsVisible: Bool) {
        refreshTask?.cancel()
        let interval = RefreshPolicy.interval(panelIsVisible: panelIsVisible)
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.store.refresh()
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    return
                }
            }
        }
    }
}
