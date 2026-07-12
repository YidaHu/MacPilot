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
    private let rocket = RocketShapeView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(rocket)
    }

    required init?(coder: NSCoder) { nil }

    func start(completion: @escaping () -> Void) {
        let size = NSSize(width: 180, height: 130)
        rocket.frame = NSRect(x: -size.width, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
        rocket.prepareForDisplay()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            rocket.animator().frame.origin.x = bounds.maxX + size.width
        } completionHandler: { completion() }
    }
}

private final class RocketShapeView: NSView {
    private let flame = CAShapeLayer()
    private let innerFlame = CAShapeLayer()
    private let body = CAShapeLayer()
    private let nose = CAShapeLayer()
    private let topFin = CAShapeLayer()
    private let bottomFin = CAShapeLayer()
    private let windowLayer = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { nil }

    func prepareForDisplay() {
        installLayersIfNeeded()
        updatePaths()
    }

    override func layout() {
        super.layout()
        updatePaths()
    }

    private func installLayersIfNeeded() {
        guard let root = layer, body.superlayer == nil else { return }
        configure(flame, fill: NSColor(calibratedRed: 0.96, green: 0.35, blue: 0.10, alpha: 0.92))
        configure(innerFlame, fill: NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.22, alpha: 0.96))
        configure(body, fill: NSColor(calibratedRed: 0.86, green: 0.92, blue: 1.0, alpha: 1), stroke: NSColor(calibratedRed: 0.18, green: 0.46, blue: 0.88, alpha: 1), width: 3)
        configure(nose, fill: .systemRed)
        configure(topFin, fill: .systemRed)
        configure(bottomFin, fill: .systemRed)
        configure(windowLayer, fill: NSColor(calibratedRed: 0.55, green: 0.86, blue: 1.0, alpha: 1), stroke: NSColor(calibratedRed: 0.12, green: 0.28, blue: 0.48, alpha: 1), width: 3)
        [flame, innerFlame, body, nose, topFin, bottomFin, windowLayer].forEach(root.addSublayer)
    }

    private func updatePaths() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let sx = bounds.width / 180
        let sy = bounds.height / 130
        var transform = CGAffineTransform(scaleX: sx, y: sy)
        let frame = CGRect(origin: .zero, size: bounds.size)
        [flame, innerFlame, body, nose, topFin, bottomFin, windowLayer].forEach { $0.frame = frame }
        flame.path = polygon([(34,65),(4,38),(16,65),(4,92)]).copy(using: &transform)
        innerFlame.path = polygon([(30,65),(12,50),(20,65),(12,80)]).copy(using: &transform)
        body.path = CGPath(roundedRect: CGRect(x: 42, y: 38, width: 90, height: 54), cornerWidth: 27, cornerHeight: 27, transform: &transform)
        nose.path = polygon([(126,38),(170,65),(126,92)]).copy(using: &transform)
        topFin.path = polygon([(72,40),(94,12),(102,43)]).copy(using: &transform)
        bottomFin.path = polygon([(72,90),(94,118),(102,87)]).copy(using: &transform)
        windowLayer.path = CGPath(ellipseIn: CGRect(x: 91, y: 52, width: 26, height: 26), transform: &transform)
    }

    private func polygon(_ points: [(CGFloat, CGFloat)]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.0, y: first.1))
        for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
        path.closeSubpath()
        return path
    }

    private func configure(_ shape: CAShapeLayer, fill: NSColor, stroke: NSColor? = nil, width: CGFloat = 0) {
        shape.fillColor = fill.cgColor
        shape.strokeColor = stroke?.cgColor
        shape.lineWidth = width
        shape.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
    }
}
