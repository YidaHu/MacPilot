import AppKit
import QuartzCore

@MainActor
public final class RocketOverlayWindow: RocketReminderPresenting {
    private var activePanel: NSPanel?
    public init() {}

    public nonisolated func presentRocket() {
        Task { @MainActor [weak self] in self?.showRocket() }
    }

    public func resetAfterDisplayChange() {
        activePanel?.close()
        activePanel = nil
    }

    private func showRocket() {
        activePanel?.close()
        guard let screen = NSScreen.main else { return }
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let view = RocketAnimationView(frame: NSRect(origin: .zero, size: screen.frame.size))
        panel.contentView = view
        panel.orderFrontRegardless()
        activePanel = panel
        view.start { [weak self, weak panel] in
            panel?.close()
            if self?.activePanel === panel { self?.activePanel = nil }
        }
    }
}

private final class RocketAnimationView: NSView {
    private let rocket = NSTextField(labelWithString: "🚀")
    override init(frame: NSRect) {
        super.init(frame: frame)
        rocket.font = .systemFont(ofSize: 96)
        addSubview(rocket)
    }
    required init?(coder: NSCoder) { nil }

    func start(completion: @escaping () -> Void) {
        let size = NSSize(width: 140, height: 120)
        rocket.frame = NSRect(x: -size.width, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            rocket.animator().frame.origin.x = bounds.maxX + size.width
        } completionHandler: { completion() }
    }
}
