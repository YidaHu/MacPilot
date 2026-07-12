import AppKit
import ApplicationServices
import SwiftUI

enum CleaningSessionError: LocalizedError {
    case accessibilityRequired
    case eventTapUnavailable

    var errorDescription: String? {
        switch self {
        case .accessibilityRequired: return "清洁键盘需要辅助功能权限"
        case .eventTapUnavailable: return "无法创建键盘拦截会话"
        }
    }
}

@MainActor
final class CleaningOverlayController: NSObject {
    private var panel: NSPanel?
    private var timer: Timer?
    private var blocker: KeyboardEventBlocker?
    private var remainingSeconds = 0
    private var overlayTitle = ""
    private var overlayDetail = ""

    func showScreenCleaning(duration: TimeInterval = 30) {
        showOverlay(title: "清洁屏幕", detail: "屏幕已变暗，点击任意位置不会操作原窗口", duration: duration)
    }

    func showKeyboardCleaning(duration: TimeInterval = 30) throws {
        guard AXIsProcessTrusted() else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            throw CleaningSessionError.accessibilityRequired
        }
        let blocker = KeyboardEventBlocker { [weak self] in self?.stop() }
        guard blocker.start() else { throw CleaningSessionError.eventTapUnavailable }
        self.blocker = blocker
        showOverlay(title: "清洁键盘", detail: "键盘输入已暂停 · 按 ⌃⌥⌘Esc 随时退出", duration: duration)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        blocker?.stop()
        blocker = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    private func showOverlay(title: String, detail: String, duration: TimeInterval) {
        stopOverlayOnly()
        guard let screen = NSScreen.main else { return }
        remainingSeconds = max(Int(duration.rounded(.up)), 1)
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.level = .screenSaver
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(
            rootView: CleaningOverlayView(title: title, detail: detail, seconds: remainingSeconds) { [weak self] in
                self?.stop()
            }
        )
        panel.orderFrontRegardless()
        self.panel = panel
        overlayTitle = title
        overlayDetail = detail
        timer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(timerDidFire(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func timerDidFire(_ timer: Timer) {
        tick(title: overlayTitle, detail: overlayDetail)
    }

    private func tick(title: String, detail: String) {
        remainingSeconds -= 1
        guard remainingSeconds > 0 else { stop(); return }
        panel?.contentViewController = NSHostingController(
            rootView: CleaningOverlayView(title: title, detail: detail, seconds: remainingSeconds) { [weak self] in
                self?.stop()
            }
        )
    }

    private func stopOverlayOnly() {
        timer?.invalidate()
        timer = nil
        panel?.close()
        panel = nil
    }
}

private struct CleaningOverlayView: View {
    let title: String
    let detail: String
    let seconds: Int
    let stop: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles").font(.system(size: 38))
            Text(title).font(.title2.weight(.semibold))
            Text(detail).foregroundColor(.secondary)
            Text("\(seconds) 秒").font(.system(size: 28, weight: .light, design: .rounded))
            Button("立即退出", action: stop).keyboardShortcut(.escape, modifiers: [])
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

private final class KeyboardEventBlocker {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let onExit: () -> Void

    init(onExit: @escaping () -> Void) { self.onExit = onExit }

    func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: keyboardBlockerCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        source = nil
        tap = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let flags = event.flags
        let exitModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
        let isExit = type == .keyDown
            && event.getIntegerValueField(.keyboardEventKeycode) == 53
            && flags.intersection(exitModifiers) == exitModifiers
        if isExit {
            DispatchQueue.main.async { [weak self] in self?.onExit() }
            return Unmanaged.passUnretained(event)
        }
        return nil
    }
}

private let keyboardBlockerCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let blocker = Unmanaged<KeyboardEventBlocker>.fromOpaque(userInfo).takeUnretainedValue()
    return blocker.handle(type: type, event: event)
}
