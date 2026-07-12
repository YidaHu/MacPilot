import XCTest
@testable import MacPilotCalendar

final class RocketGeometryTests: XCTestCase {
    func testRocketNosePointsHorizontallyRight() {
        let geometry = RocketGeometry(size: CGSize(width: 180, height: 130))

        XCTAssertGreaterThan(geometry.noseTip.x, geometry.bodyRect.maxX)
        XCTAssertEqual(geometry.noseTip.y, geometry.bodyRect.midY, accuracy: 0.001)
        XCTAssertEqual(geometry.flightAngleRadians, 0, accuracy: 0.001)
    }
}
