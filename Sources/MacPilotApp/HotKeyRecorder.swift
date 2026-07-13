import AppKit
import MacPilotVoice
import SwiftUI

@MainActor
struct HotKeyRecorder: NSViewRepresentable {
    let descriptor: HotKeyDescriptor
    let onCapture: @MainActor (HotKeyDescriptor) -> Void
    let onRecordingChanged: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        RecorderButton(
            descriptor: descriptor,
            onCapture: onCapture,
            onRecordingChanged: onRecordingChanged
        )
    }

    func updateNSView(_ view: RecorderButton, context: Context) {
        view.descriptor = descriptor
        view.onCapture = onCapture
        view.onRecordingChanged = onRecordingChanged
        view.refreshTitle()
    }
}

@MainActor
final class RecorderButton: NSButton {
    var descriptor: HotKeyDescriptor
    var onCapture: @MainActor (HotKeyDescriptor) -> Void
    var onRecordingChanged: @MainActor (Bool) -> Void
    private var isRecording = false

    init(
        descriptor: HotKeyDescriptor,
        onCapture: @escaping @MainActor (HotKeyDescriptor) -> Void,
        onRecordingChanged: @escaping @MainActor (Bool) -> Void
    ) {
        self.descriptor = descriptor
        self.onCapture = onCapture
        self.onRecordingChanged = onRecordingChanged
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        focusRingType = .exterior
        refreshTitle()
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard !isRecording else { return }
        isRecording = true
        onRecordingChanged(true)
        refreshTitle()
        _ = window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            finishRecording()
            return
        }

        let keyCode = UInt32(event.keyCode)
        guard HotKeyDescriptor.supports(keyCode: keyCode) else {
            NSSound.beep()
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let captured = HotKeyDescriptor(
            keyCode: keyCode,
            command: flags.contains(.command),
            option: flags.contains(.option),
            control: flags.contains(.control),
            shift: flags.contains(.shift)
        )
        descriptor = captured
        onCapture(captured)
        finishRecording()
    }

    override func flagsChanged(with event: NSEvent) {
        // A modifier on its own is not a complete shortcut.
    }

    override func resignFirstResponder() -> Bool {
        finishRecording()
        return super.resignFirstResponder()
    }

    fileprivate func refreshTitle() {
        title = isRecording ? "请按下新的快捷键…" : descriptor.displayValue
    }

    private func finishRecording() {
        guard isRecording else { return }
        isRecording = false
        onRecordingChanged(false)
        refreshTitle()
    }
}
