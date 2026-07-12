import AppKit
import Combine
import MacPilotCore
import MacPilotVoice
import SwiftUI

@MainActor
final class FloatingVoiceCapsuleController: NSObject {
    private final class CapsulePanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private enum Keys {
        static let screen = "voice.capsule.screen"
        static let xFraction = "voice.capsule.xFraction"
        static let yFraction = "voice.capsule.yFraction"
    }

    private let panel: CapsulePanel
    private let store: VoiceStore
    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []
    private var notificationTokens: [NSObjectProtocol] = []
    private var isPositioned = false
    private var dragOrigin: NSPoint?

    init(store: VoiceStore, defaults: UserDefaults = .standard, openSettings: @escaping (SettingsSection) -> Void) {
        self.store = store
        self.defaults = defaults
        panel = CapsulePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.contentViewController = NSHostingController(
            rootView: FloatingVoiceCapsuleView(
                store: store,
                onDrag: { [weak self] translation, ended in self?.drag(translation: translation, ended: ended) },
                openSettings: { openSettings(store.errorSettingsSection) }
            )
        )
        bindState()
        observeDisplays()
    }

    func shutdown() {
        cancellables.removeAll()
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        notificationTokens.removeAll()
        panel.orderOut(nil)
    }

    private func bindState() {
        store.$capsuleState
            .combineLatest(store.$capsuleAutoHide)
            .receive(on: RunLoop.main)
            .sink { [weak self] state, autoHide in self?.apply(state: state, autoHide: autoHide) }
            .store(in: &cancellables)
    }

    private func observeDisplays() {
        notificationTokens.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.revalidatePosition() } })
        notificationTokens.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.revalidatePosition() } })
    }

    private func apply(state: CapsuleDisplayState, autoHide: Bool) {
        let contentSize = CapsuleLayout.size(for: state)
        let windowSize = NSSize(width: contentSize.width + 24, height: contentSize.height + 24)
        let targetScreen = screen(for: panel.frame) ?? preferredScreen()
        let visible = rect(targetScreen.visibleFrame)

        let origin: CapsulePoint
        if !isPositioned {
            origin = restoredOrigin(size: windowSize, screen: targetScreen)
            isPositioned = true
        } else {
            let current = panel.frame
            origin = CapsuleLayout.clamp(
                origin: .init(x: current.minX, y: current.midY - windowSize.height / 2),
                size: .init(width: windowSize.width, height: windowSize.height),
                visibleFrame: visible
            )
        }
        panel.setFrame(NSRect(origin: .init(x: origin.x, y: origin.y), size: windowSize), display: true, animate: false)

        if CapsuleLayout.isVisible(state: state, autoHide: autoHide) {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func drag(translation: CGSize, ended: Bool) {
        if dragOrigin == nil { dragOrigin = panel.frame.origin }
        guard let start = dragOrigin else { return }
        let proposed = CapsulePoint(x: start.x + translation.width, y: start.y - translation.height)
        let targetScreen = screen(containing: proposed) ?? screen(for: panel.frame) ?? preferredScreen()
        let clamped = CapsuleLayout.clamp(
            origin: proposed,
            size: .init(width: panel.frame.width, height: panel.frame.height),
            visibleFrame: rect(targetScreen.visibleFrame)
        )
        panel.setFrameOrigin(.init(x: clamped.x, y: clamped.y))
        if ended {
            persistPosition(on: targetScreen)
            dragOrigin = nil
        }
    }

    private func revalidatePosition() {
        guard isPositioned else { return }
        let target = screen(for: panel.frame) ?? preferredScreen()
        let clamped = CapsuleLayout.clamp(
            origin: .init(x: panel.frame.minX, y: panel.frame.minY),
            size: .init(width: panel.frame.width, height: panel.frame.height),
            visibleFrame: rect(target.visibleFrame)
        )
        panel.setFrameOrigin(.init(x: clamped.x, y: clamped.y))
        persistPosition(on: target)
    }

    private func restoredOrigin(size: NSSize, screen: NSScreen) -> CapsulePoint {
        let frame = screen.visibleFrame
        guard defaults.object(forKey: Keys.xFraction) != nil,
              defaults.object(forKey: Keys.yFraction) != nil else {
            return CapsuleLayout.defaultOrigin(
                size: .init(width: size.width, height: size.height),
                visibleFrame: rect(frame)
            )
        }
        let xRange = max(frame.width - size.width, 0)
        let yRange = max(frame.height - size.height, 0)
        return CapsuleLayout.clamp(
            origin: .init(
                x: frame.minX + min(max(defaults.double(forKey: Keys.xFraction), 0), 1) * xRange,
                y: frame.minY + min(max(defaults.double(forKey: Keys.yFraction), 0), 1) * yRange
            ),
            size: .init(width: size.width, height: size.height),
            visibleFrame: rect(frame)
        )
    }

    private func persistPosition(on screen: NSScreen) {
        let frame = screen.visibleFrame
        let xRange = max(frame.width - panel.frame.width, 1)
        let yRange = max(frame.height - panel.frame.height, 1)
        defaults.set((panel.frame.minX - frame.minX) / xRange, forKey: Keys.xFraction)
        defaults.set((panel.frame.minY - frame.minY) / yRange, forKey: Keys.yFraction)
        defaults.set(screenIdentifier(screen), forKey: Keys.screen)
    }

    private func preferredScreen() -> NSScreen {
        if let identifier = defaults.string(forKey: Keys.screen),
           let saved = NSScreen.screens.first(where: { screenIdentifier($0) == identifier }) { return saved }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func screen(for frame: NSRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            lhs.visibleFrame.intersection(frame).area < rhs.visibleFrame.intersection(frame).area
        }.flatMap { $0.visibleFrame.intersects(frame) ? $0 : nil }
    }

    private func screen(containing origin: CapsulePoint) -> NSScreen? {
        NSScreen.screens.first { $0.visibleFrame.contains(.init(x: origin.x, y: origin.y)) }
    }

    private func screenIdentifier(_ screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? "main"
    }

    private func rect(_ value: NSRect) -> CapsuleRect {
        .init(x: value.minX, y: value.minY, width: value.width, height: value.height)
    }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
