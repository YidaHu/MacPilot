import Combine
import Foundation

@MainActor
public final class FanStore: ObservableObject {
    public typealias SnapshotProvider = () throws -> FanSnapshot
    public typealias ManualSender = (Int, Double, UUID, Date) async throws -> Void
    public typealias LeaseRenewer = (UUID, Date) async throws -> Void
    public typealias AutomaticRestorer = ([Int]) async throws -> Void

    @Published public private(set) var snapshot: FanSnapshot?
    @Published public private(set) var selectedPreset: FanPreset = .automatic
    @Published public private(set) var errorDescription: String?
    @Published public private(set) var isInstallingHelper = false
    @Published public private(set) var manualTargets: [Int: Double] = [:]

    private let snapshotProvider: SnapshotProvider
    private let helperIsInstalled: () -> Bool
    private let installHelper: () throws -> Void
    private let setManual: ManualSender
    private let renew: LeaseRenewer
    private let restoreAutomaticAction: AutomaticRestorer
    private let interRequestDelay: () async -> Void
    private var helperReady: Bool
    private var leaseID: UUID?
    private var renewalTask: Task<Void, Never>?

    public init(
        snapshotProvider: @escaping SnapshotProvider,
        helperIsInstalled: @escaping () -> Bool,
        installHelper: @escaping () throws -> Void,
        setManual: @escaping ManualSender,
        renew: @escaping LeaseRenewer,
        restoreAutomatic: @escaping AutomaticRestorer,
        interRequestDelay: @escaping () async -> Void
    ) {
        self.snapshotProvider = snapshotProvider
        self.helperIsInstalled = helperIsInstalled
        self.installHelper = installHelper
        self.setManual = setManual
        self.renew = renew
        self.restoreAutomaticAction = restoreAutomatic
        self.interRequestDelay = interRequestDelay
        self.helperReady = helperIsInstalled()
    }

    deinit { renewalTask?.cancel() }

    public static func live() -> FanStore {
        do {
            let connection = try AppleSMCConnection()
            let client = FanHelperClient()
            let installer = FanHelperInstaller()
            return FanStore(
                snapshotProvider: { try IntelFanReader(reader: connection).readSnapshot() },
                helperIsInstalled: {
                    FileManager.default.isExecutableFile(atPath: "/Library/PrivilegedHelperTools/\(FanHelperInstaller.label)")
                },
                installHelper: { try installer.install() },
                setManual: { try await client.setManual(fanIndex: $0, targetRPM: $1, leaseID: $2, expiresAt: $3) },
                renew: { try await client.renew(leaseID: $0, expiresAt: $1) },
                restoreAutomatic: { try await client.restoreAutomatic(fanIndices: $0) },
                interRequestDelay: {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                }
            )
        } catch {
            return FanStore(
                snapshotProvider: { throw error },
                helperIsInstalled: { false },
                installHelper: { throw error },
                setManual: { _, _, _, _ in throw error },
                renew: { _, _ in throw error },
                restoreAutomatic: { _ in throw error },
                interRequestDelay: {}
            )
        }
    }

    public func refresh() {
        do {
            snapshot = try snapshotProvider()
            errorDescription = nil
        } catch {
            errorDescription = String(describing: error)
        }
    }

    public func applyPreset(_ preset: FanPreset, manualNormalized: Double = 0.5) async {
        guard preset != .automatic else {
            await restoreAutomatic()
            return
        }
        guard let snapshot else {
            errorDescription = "尚未读取风扇状态"
            return
        }
        let targets = preset.targets(for: snapshot.fans, manualNormalized: manualNormalized)
        guard targets.count == snapshot.fans.count else {
            errorDescription = "无法验证全部风扇的安全范围"
            return
        }

        do {
            try ensureHelperInstalled()
            let leaseID = self.leaseID ?? UUID()
            self.leaseID = leaseID
            let entries = targets.sorted { $0.key < $1.key }
            for (position, entry) in entries.enumerated() {
                try await setManual(entry.key, entry.value, leaseID, Date().addingTimeInterval(5))
                if position < entries.count - 1 { await interRequestDelay() }
            }
            manualTargets = targets
            selectedPreset = preset
            errorDescription = nil
            startRenewingLease(leaseID)
        } catch {
            errorDescription = String(describing: error)
            await restoreAutomatic()
        }
    }

    public func setManualRPM(fanIndex: Int, rpm: Double) async {
        guard let fan = snapshot?.fans.first(where: { $0.index == fanIndex }),
              let minimum = fan.minimumRPM, let maximum = fan.maximumRPM else { return }
        let clamped = min(max(rpm, minimum), maximum)
        do {
            try ensureHelperInstalled()
            let leaseID = self.leaseID ?? UUID()
            self.leaseID = leaseID
            try await setManual(fanIndex, clamped, leaseID, Date().addingTimeInterval(5))
            manualTargets[fanIndex] = clamped
            selectedPreset = .manual
            errorDescription = nil
            startRenewingLease(leaseID)
        } catch {
            errorDescription = String(describing: error)
            await restoreAutomatic()
        }
    }

    public func restoreAutomatic() async {
        renewalTask?.cancel()
        renewalTask = nil
        if helperReady, let indices = snapshot?.fans.map(\.index), !indices.isEmpty {
            do { try await restoreAutomaticAction(indices) }
            catch { errorDescription = String(describing: error); return }
        }
        leaseID = nil
        manualTargets = [:]
        selectedPreset = .automatic
    }

    private func ensureHelperInstalled() throws {
        if helperReady || helperIsInstalled() { helperReady = true; return }
        isInstallingHelper = true
        defer { isInstallingHelper = false }
        try installHelper()
        helperReady = true
    }

    private func startRenewingLease(_ leaseID: UUID) {
        renewalTask?.cancel()
        renewalTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 2_000_000_000) }
                catch { return }
                guard let self else { return }
                do { try await self.renew(leaseID, Date().addingTimeInterval(5)) }
                catch {
                    self.errorDescription = String(describing: error)
                    await self.restoreAutomatic()
                    return
                }
            }
        }
    }
}
