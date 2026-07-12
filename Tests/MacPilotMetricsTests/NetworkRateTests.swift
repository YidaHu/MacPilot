import XCTest
@testable import MacPilotMetrics

final class NetworkRateTests: XCTestCase {
    func testNetworkRateUsesByteDelta() {
        let old = NetworkCounters(
            received: 1_000,
            sent: 500,
            at: Date(timeIntervalSince1970: 10)
        )
        let new = NetworkCounters(
            received: 3_000,
            sent: 1_000,
            at: Date(timeIntervalSince1970: 12)
        )

        XCTAssertEqual(
            NetworkRate.between(old, new),
            NetworkRate(download: 1_000, upload: 250)
        )
    }

    func testNetworkRateReturnsZeroForCounterReset() {
        let old = NetworkCounters(received: 10, sent: 10, at: Date(timeIntervalSince1970: 10))
        let new = NetworkCounters(received: 1, sent: 1, at: Date(timeIntervalSince1970: 11))
        XCTAssertEqual(NetworkRate.between(old, new), .zero)
    }

    func testNetworkRateReturnsZeroForZeroElapsedTime() {
        let date = Date(timeIntervalSince1970: 10)
        let old = NetworkCounters(received: 1, sent: 1, at: date)
        let new = NetworkCounters(received: 2, sent: 2, at: date)
        XCTAssertEqual(NetworkRate.between(old, new), .zero)
    }

    func testOpenWiFiWithoutVPNNeedsAttention() {
        XCTAssertEqual(
            NetworkRiskEvaluator.evaluate(
                isWiFi: true,
                isEncryptedWiFi: false,
                hasVPN: false,
                hasProxy: false
            ).risk,
            .attention
        )
    }

    func testVPNMakesConnectionNormal() {
        XCTAssertEqual(
            NetworkRiskEvaluator.evaluate(
                isWiFi: true,
                isEncryptedWiFi: false,
                hasVPN: true,
                hasProxy: false
            ).risk,
            .normal
        )
    }
}
