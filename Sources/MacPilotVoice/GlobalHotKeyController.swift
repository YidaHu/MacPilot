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

    public mutating func reset() { recording = false }
}

public enum HotKeyError: Error, Equatable {
    case invalidShortcut(String)
    case registrationFailed(OSStatus)
}

public struct HotKeyDescriptor: Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32

    public static let defaultVoice = try! HotKeyDescriptor.parse("Option+/")

    private static let keys: [(name: String, code: UInt32)] = [
        ("A", 0), ("S", 1), ("D", 2), ("F", 3), ("H", 4), ("G", 5),
        ("Z", 6), ("X", 7), ("C", 8), ("V", 9), ("B", 11), ("Q", 12),
        ("W", 13), ("E", 14), ("R", 15), ("Y", 16), ("T", 17), ("1", 18),
        ("2", 19), ("3", 20), ("4", 21), ("6", 22), ("5", 23), ("=", 24),
        ("9", 25), ("7", 26), ("-", 27), ("8", 28), ("0", 29), ("]", 30),
        ("O", 31), ("U", 32), ("[", 33), ("I", 34), ("P", 35), ("Return", 36),
        ("L", 37), ("J", 38), ("'", 39), ("K", 40), (";", 41), ("\\", 42),
        (",", 43), ("/", 44), ("N", 45), ("M", 46), (".", 47), ("Tab", 48),
        ("Space", 49), ("`", 50), ("Delete", 51), ("F17", 64), ("F18", 79),
        ("F19", 80), ("F20", 90), ("F5", 96), ("F6", 97), ("F7", 98),
        ("F3", 99), ("F8", 100), ("F9", 101), ("F11", 103), ("F13", 105),
        ("F16", 106), ("F14", 107), ("F10", 109), ("F12", 111), ("F15", 113),
        ("Home", 115), ("PageUp", 116), ("ForwardDelete", 117), ("F4", 118),
        ("End", 119), ("F2", 120), ("PageDown", 121), ("F1", 122),
        ("Left", 123), ("Right", 124), ("Down", 125), ("Up", 126)
    ]

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public init(
        keyCode: UInt32,
        command: Bool,
        option: Bool,
        control: Bool,
        shift: Bool
    ) {
        var modifiers: UInt32 = 0
        if command { modifiers |= UInt32(cmdKey) }
        if option { modifiers |= UInt32(optionKey) }
        if control { modifiers |= UInt32(controlKey) }
        if shift { modifiers |= UInt32(shiftKey) }
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    public static func parse(_ value: String) throws -> HotKeyDescriptor {
        let parts = value.split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces).lowercased() }
        guard let key = parts.last, !key.isEmpty else { throw HotKeyError.invalidShortcut(value) }
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
        guard let keyCode = keys.first(where: { $0.name.lowercased() == key })?.code else {
            throw HotKeyError.invalidShortcut(value)
        }
        return HotKeyDescriptor(keyCode: keyCode, modifiers: modifiers)
    }

    public static func resolve(_ value: String?) -> HotKeyDescriptor {
        guard let value else { return .defaultVoice }
        return (try? parse(value)) ?? .defaultVoice
    }

    public static func supports(keyCode: UInt32) -> Bool {
        keys.contains(where: { $0.code == keyCode })
    }

    public var storageValue: String {
        let key = Self.keys.first(where: { $0.code == keyCode })?.name ?? ""
        return (modifierNames + [key]).joined(separator: "+")
    }

    public var displayValue: String {
        let symbols: [(UInt32, String)] = [
            (UInt32(cmdKey), "⌘"),
            (UInt32(optionKey), "⌥"),
            (UInt32(controlKey), "⌃"),
            (UInt32(shiftKey), "⇧")
        ]
        let modifierSymbols = symbols.compactMap { modifiers & $0.0 != 0 ? $0.1 : nil }
        let key = Self.keys.first(where: { $0.code == keyCode })?.name ?? "未知按键"
        let displayKeys = [
            "Return": "↩", "Tab": "⇥", "Delete": "⌫", "ForwardDelete": "⌦",
            "Left": "←", "Right": "→", "Down": "↓", "Up": "↑",
            "PageUp": "Page Up", "PageDown": "Page Down"
        ]
        return (modifierSymbols + [displayKeys[key] ?? key]).joined(separator: " ")
    }

    public var hasModifiers: Bool { modifiers != 0 }

    private var modifierNames: [String] {
        let names: [(UInt32, String)] = [
            (UInt32(cmdKey), "Command"),
            (UInt32(optionKey), "Option"),
            (UInt32(controlKey), "Control"),
            (UInt32(shiftKey), "Shift")
        ]
        return names.compactMap { modifiers & $0.0 != 0 ? $0.1 : nil }
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

    public func resetInteraction() { interaction.reset() }

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
