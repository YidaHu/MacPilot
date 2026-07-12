import XCTest
@testable import MacPilotFan

@MainActor
final class FanStoreTests: XCTestCase {
    func testRefreshPublishesFanSnapshot() {
        let expected = snapshot()
        let store = makeStore(snapshot: expected)

        store.refresh()

        XCTAssertEqual(store.snapshot, expected)
        XCTAssertNil(store.errorDescription)
    }

    func testAutomaticPresetNeverInstallsHelper() async {
        var installCount = 0
        let store = makeStore(snapshot: snapshot(), install: { installCount += 1 })
        store.refresh()

        await store.applyPreset(.automatic)

        XCTAssertEqual(installCount, 0)
    }

    func testBalancedPresetInstallsAndSendsBothBoundedTargets() async {
        var installCount = 0
        var calls: [(Int, Double)] = []
        let store = makeStore(
            snapshot: snapshot(),
            install: { installCount += 1 },
            setManual: { index, rpm, _, _ in calls.append((index, rpm)) }
        )
        store.refresh()

        await store.applyPreset(.balanced)

        XCTAssertEqual(installCount, 1)
        XCTAssertEqual(calls.map(\.0), [0, 1])
        XCTAssertEqual(calls[0].1, 3_785, accuracy: 0.1)
        XCTAssertEqual(calls[1].1, 3_925, accuracy: 0.1)
        XCTAssertEqual(store.selectedPreset, .balanced)
    }

    private func makeStore(
        snapshot: FanSnapshot,
        install: @escaping () throws -> Void = {},
        setManual: @escaping (Int, Double, UUID, Date) async throws -> Void = { _, _, _, _ in }
    ) -> FanStore {
        FanStore(
            snapshotProvider: { snapshot },
            helperIsInstalled: { false },
            installHelper: install,
            setManual: setManual,
            renew: { _, _ in },
            restoreAutomatic: { _ in },
            interRequestDelay: {}
        )
    }

    private func snapshot() -> FanSnapshot {
        FanSnapshot(fans: [
            FanStatus(index: 0, actualRPM: 2_000, minimumRPM: 1_200, maximumRPM: 5_900, targetRPM: 2_100, controlAvailability: .available),
            FanStatus(index: 1, actualRPM: 2_100, minimumRPM: 2_000, maximumRPM: 5_500, targetRPM: 2_200, controlAvailability: .available)
        ], sampledAt: Date(timeIntervalSince1970: 1_000))
    }
}
