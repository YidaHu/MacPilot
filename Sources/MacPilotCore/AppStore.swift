import Combine
import Foundation

@MainActor
public final class AppStore: ObservableObject {
    @Published public private(set) var snapshot: SystemSnapshot?
    @Published public private(set) var lastErrorDescription: String?

    private let metrics: any MetricsProviding

    public init(metrics: any MetricsProviding) {
        self.metrics = metrics
    }

    public func refresh() async {
        do {
            snapshot = try await metrics.sample()
            lastErrorDescription = nil
        } catch {
            lastErrorDescription = error.localizedDescription
        }
    }
}
