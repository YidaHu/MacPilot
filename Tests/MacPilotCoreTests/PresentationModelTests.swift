import XCTest
@testable import MacPilotCore

final class PresentationModelTests: XCTestCase {
    func testDashboardHasApprovedTabOrder() {
        XCTAssertEqual(DashboardTab.allCases, [.overview, .fans, .tools, .voice])
    }

    func testSettingsHasTwelveApprovedSections() {
        XCTAssertEqual(SettingsSection.allCases.count, 12)
        XCTAssertEqual(SettingsSection.allCases.first, .general)
        XCTAssertEqual(SettingsSection.allCases.last, .about)
    }

    func testRefreshPolicyUsesFastIntervalOnlyWhenPanelIsVisible() {
        XCTAssertEqual(RefreshPolicy.interval(panelIsVisible: true), 1)
        XCTAssertEqual(RefreshPolicy.interval(panelIsVisible: false), 15)
    }
}
