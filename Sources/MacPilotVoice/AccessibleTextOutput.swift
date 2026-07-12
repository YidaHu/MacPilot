import AppKit
import ApplicationServices
@preconcurrency import Foundation

public enum AccessibleTextOutputError: Error, Equatable {
    case accessibilityPermissionRequired
    case clipboardWriteFailed
    case pasteEventUnavailable
}

struct PasteboardItemSnapshot: Equatable, Sendable {
    let values: [String: Data]
}

struct PasteboardSnapshot: Equatable, Sendable {
    let items: [PasteboardItemSnapshot]
}

protocol AccessibilityChecking: Sendable {
    func isTrusted(prompt: Bool) -> Bool
}

protocol PasteboardManaging: Sendable {
    var changeCount: Int { get }
    func snapshot() -> PasteboardSnapshot
    func writeText(_ text: String) throws -> Int
    func restore(_ snapshot: PasteboardSnapshot) throws
}

protocol PasteKeyPosting: Sendable {
    func postPaste() throws
}

public final class AccessibleTextOutput: @unchecked Sendable, TextOutputting {
    private let accessibility: any AccessibilityChecking
    private let pasteboard: any PasteboardManaging
    private let keyPoster: any PasteKeyPosting
    private let restoreDelayNanoseconds: UInt64

    public convenience init() {
        self.init(
            accessibility: SystemAccessibilityChecker(),
            pasteboard: SystemPasteboardManager(),
            keyPoster: SystemPasteKeyPoster(),
            restoreDelayNanoseconds: 120_000_000
        )
    }

    init(
        accessibility: any AccessibilityChecking,
        pasteboard: any PasteboardManaging,
        keyPoster: any PasteKeyPosting,
        restoreDelayNanoseconds: UInt64
    ) {
        self.accessibility = accessibility
        self.pasteboard = pasteboard
        self.keyPoster = keyPoster
        self.restoreDelayNanoseconds = restoreDelayNanoseconds
    }

    public func output(_ text: String) async throws {
        guard accessibility.isTrusted(prompt: true) else {
            throw AccessibleTextOutputError.accessibilityPermissionRequired
        }

        let previous = pasteboard.snapshot()
        let ownedChangeCount = try pasteboard.writeText(text)
        do {
            try keyPoster.postPaste()
            if restoreDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: restoreDelayNanoseconds)
            }
        } catch {
            if pasteboard.changeCount == ownedChangeCount { try? pasteboard.restore(previous) }
            throw error
        }

        // Do not overwrite clipboard content copied by the user while output was in flight.
        if pasteboard.changeCount == ownedChangeCount {
            try pasteboard.restore(previous)
        }
    }
}

private struct SystemAccessibilityChecker: AccessibilityChecking {
    func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

private final class SystemPasteboardManager: @unchecked Sendable, PasteboardManaging {
    private var pasteboard: NSPasteboard { .general }
    var changeCount: Int { pasteboard.changeCount }

    func snapshot() -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            var values: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { values[type.rawValue] = data }
            }
            return PasteboardItemSnapshot(values: values)
        }
        return PasteboardSnapshot(items: items)
    }

    func writeText(_ text: String) throws -> Int {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw AccessibleTextOutputError.clipboardWriteFailed
        }
        return pasteboard.changeCount
    }

    func restore(_ snapshot: PasteboardSnapshot) throws {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }
        let items = snapshot.items.map { stored -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (rawType, data) in stored.values {
                item.setData(data, forType: NSPasteboard.PasteboardType(rawValue: rawType))
            }
            return item
        }
        guard pasteboard.writeObjects(items) else {
            throw AccessibleTextOutputError.clipboardWriteFailed
        }
    }
}

private struct SystemPasteKeyPoster: PasteKeyPosting {
    func postPaste() throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw AccessibleTextOutputError.pasteEventUnavailable
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
