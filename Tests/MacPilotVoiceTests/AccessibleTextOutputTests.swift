import XCTest
@testable import MacPilotVoice

final class AccessibleTextOutputTests: XCTestCase {
    func testDeniedAccessibilityDoesNotTouchClipboard() async {
        let pasteboard = PasteboardSpy()
        let output = AccessibleTextOutput(
            accessibility: AccessibilityStub(trusted: false),
            pasteboard: pasteboard,
            keyPoster: KeyPosterSpy(),
            restoreDelayNanoseconds: 0
        )

        do {
            try await output.output("hello")
            XCTFail("Expected permission error")
        } catch {
            XCTAssertEqual(error as? AccessibleTextOutputError, .accessibilityPermissionRequired)
        }
        XCTAssertEqual(pasteboard.writeCount, 0)
    }

    func testPastesTextAndRestoresExistingClipboard() async throws {
        let original = PasteboardSnapshot(items: [.init(values: ["public.utf8-plain-text": Data("before".utf8)])])
        let pasteboard = PasteboardSpy(snapshot: original)
        let keyPoster = KeyPosterSpy()
        let output = AccessibleTextOutput(
            accessibility: AccessibilityStub(trusted: true),
            pasteboard: pasteboard,
            keyPoster: keyPoster,
            restoreDelayNanoseconds: 0
        )

        try await output.output("整理后的文字")

        XCTAssertEqual(pasteboard.writtenText, "整理后的文字")
        XCTAssertEqual(keyPoster.postCount, 1)
        XCTAssertEqual(pasteboard.restoredSnapshot, original)
    }

    func testDoesNotOverwriteClipboardChangedByAnotherApplication() async throws {
        let pasteboard = PasteboardSpy(snapshot: .init(items: []))
        let keyPoster = KeyPosterSpy { pasteboard.simulateExternalChange() }
        let output = AccessibleTextOutput(
            accessibility: AccessibilityStub(trusted: true),
            pasteboard: pasteboard,
            keyPoster: keyPoster,
            restoreDelayNanoseconds: 0
        )

        try await output.output("hello")

        XCTAssertNil(pasteboard.restoredSnapshot)
    }
}

private struct AccessibilityStub: AccessibilityChecking {
    let trusted: Bool
    func isTrusted(prompt: Bool) -> Bool { trusted }
}

private final class PasteboardSpy: @unchecked Sendable, PasteboardManaging {
    private(set) var snapshotValue: PasteboardSnapshot
    private(set) var writeCount = 0
    private(set) var writtenText: String?
    private(set) var restoredSnapshot: PasteboardSnapshot?
    private(set) var changeCount = 1

    init(snapshot: PasteboardSnapshot = .init(items: [])) { snapshotValue = snapshot }
    func snapshot() -> PasteboardSnapshot { snapshotValue }
    func writeText(_ text: String) throws -> Int {
        writeCount += 1
        writtenText = text
        changeCount += 1
        return changeCount
    }
    func restore(_ snapshot: PasteboardSnapshot) throws { restoredSnapshot = snapshot }
    func simulateExternalChange() { changeCount += 1 }
}

private final class KeyPosterSpy: @unchecked Sendable, PasteKeyPosting {
    private(set) var postCount = 0
    private let onPost: () -> Void
    init(onPost: @escaping () -> Void = {}) { self.onPost = onPost }
    func postPaste() throws { postCount += 1; onPost() }
}
