import Carbon
import Foundation

public enum HotKeyMode: String, Equatable, Sendable { case hold, toggle }
public enum HotKeyEvent: Equatable, Sendable { case pressed, released }
public enum HotKeyAction: Equatable, Sendable { case startRecording, stopRecording, none }

public struct HotKeyInteractionState: Equatable, Sendable {
    public let mode: HotKeyMode
    private var recording = false

    public init(mode: HotKeyMode) { self.mode = mode }

    public mutating func handle(_ event: HotKeyEvent) -> HotKeyAction {
        switch mode {
        case .hold:
            if event == .pressed, !recording { recording = true; return .startRecording }
            if event == .released, recording { recording = false; return .stopRecording }
            return .none
        case .toggle:
            guard event == .pressed else { return .none }
            recording.toggle()
            return recording ? .startRecording : .stopRecording
        }
    }
}

public enum HotKeyError: Error, Equatable {
    case invalidShortcut(String)
    case registrationFailed(OSStatus)
}

public struct HotKeyDescriptor: Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static func parse(_ value: String) throws -> HotKeyDescriptor {
        let parts = value.split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces).lowercased() }
        guard let key = parts.last, parts.count >= 2 else { throw HotKeyError.invalidShortcut(value) }
        var modifiers: UInt32 = 0
        for modifier in parts.dropLast() {
            switch modifier {
            case "option", "alt": modifiers |= UInt32(optionKey)
            case "command", "cmd": modifiers |= UInt32(cmdKey)
            case "control", "ctrl": modifiers |= UInt32(controlKey)
            case "shift": modifiers |= UInt32(shiftKey)
            default: throw HotKeyError.invalidShortcut(value)
            }
        }
        let keyCodes: [String: UInt32] = ["/": 44, ".": 47, "space": 49, "r": 15]
        guard let keyCode = keyCodes[key], modifiers != 0 else { throw HotKeyError.invalidShortcut(value) }
        return HotKeyDescriptor(keyCode: keyCode, modifiers: modifiers)
    }
}

@MainActor
public final class GlobalHotKeyController {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var interaction: HotKeyInteractionState
    private let onAction: (HotKeyAction) -> Void

    public init(mode: HotKeyMode, onAction: @escaping (HotKeyAction) -> Void) {
        interaction = HotKeyInteractionState(mode: mode)
        self.onAction = onAction
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    public func register(_ descriptor: HotKeyDescriptor) throws {
        unregister()
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyHandler,
            specs.count,
            &specs,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        guard status == noErr else { throw HotKeyError.registrationFailed(status) }

        let identifier = EventHotKeyID(signature: OSType(0x4D_50_56_43), id: 1)
        let registerStatus = RegisterEventHotKey(
            descriptor.keyCode,
            descriptor.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            unregister()
            throw HotKeyError.registrationFailed(registerStatus)
        }
    }

    public func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        hotKeyRef = nil
        eventHandlerRef = nil
    }

    fileprivate func handle(kind: UInt32) {
        let event: HotKeyEvent = kind == UInt32(kEventHotKeyPressed) ? .pressed : .released
        let action = interaction.handle(event)
        if action != .none { onAction(action) }
    }
}

private let globalHotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    let controller = Unmanaged<GlobalHotKeyController>.fromOpaque(userData).takeUnretainedValue()
    let kind = GetEventKind(event)
    DispatchQueue.main.async { controller.handle(kind: kind) }
    return noErr
}
