import XCTest
@testable import MacPilotVoice

final class VoicePresentationTests: XCTestCase {
    func testAutoHideOnlyHidesIdle() {
        XCTAssertFalse(CapsuleLayout.isVisible(state: .idle, autoHide: true))
        XCTAssertTrue(CapsuleLayout.isVisible(state: .recording(level: 0.4, elapsed: 8), autoHide: true))
        XCTAssertTrue(CapsuleLayout.isVisible(state: .idle, autoHide: false))
    }

    func testApprovedStateSizes() {
        XCTAssertEqual(CapsuleLayout.size(for: .idle), .init(width: 36, height: 36))
        XCTAssertEqual(CapsuleLayout.size(for: .recording(level: 0, elapsed: 0)), .init(width: 200, height: 36))
        XCTAssertEqual(CapsuleLayout.size(for: .transcribing), .init(width: 220, height: 36))
        XCTAssertEqual(CapsuleLayout.size(for: .polishing), .init(width: 220, height: 36))
        XCTAssertEqual(CapsuleLayout.size(for: .structured), .init(width: 220, height: 36))
        XCTAssertEqual(CapsuleLayout.size(for: .outputting), .init(width: 150, height: 36))
        XCTAssertEqual(CapsuleLayout.size(for: .complete), .init(width: 100, height: 36))
        XCTAssertEqual(CapsuleLayout.size(for: .error(message: "失败", collapsed: false)), .init(width: 200, height: 36))
        XCTAssertEqual(CapsuleLayout.size(for: .error(message: "失败", collapsed: true)), .init(width: 36, height: 36))
    }

    func testPositionIsClampedInsideVisibleFrame() {
        let frame = CapsuleRect(x: 0, y: 0, width: 1_440, height: 900)
        XCTAssertEqual(
            CapsuleLayout.clamp(
                origin: .init(x: 1_500, y: -20),
                size: .init(width: 200, height: 36),
                visibleFrame: frame
            ),
            .init(x: 1_240, y: 0)
        )
    }

    func testDefaultOriginIsBottomCenteredWithEightyPointInset() {
        let frame = CapsuleRect(x: 100, y: 50, width: 1_200, height: 800)
        XCTAssertEqual(
            CapsuleLayout.defaultOrigin(size: .init(width: 200, height: 36), visibleFrame: frame),
            .init(x: 600, y: 130)
        )
    }
}
