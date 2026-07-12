public enum FanPreset: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case quiet
    case balanced
    case strongCooling
    case manual

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: return "系统自动"
        case .quiet: return "安静"
        case .balanced: return "平衡"
        case .strongCooling: return "强力散热"
        case .manual: return "手动"
        }
    }

    public func targets(for fans: [FanStatus], manualNormalized: Double = 0.5) -> [Int: Double] {
        guard self != .automatic else { return [:] }
        let normalized: Double
        switch self {
        case .automatic: return [:]
        case .quiet: normalized = 0.25
        case .balanced: normalized = 0.55
        case .strongCooling: normalized = 0.85
        case .manual: normalized = min(max(manualNormalized, 0), 1)
        }

        return Dictionary(uniqueKeysWithValues: fans.compactMap { fan in
            guard let minimum = fan.minimumRPM, let maximum = fan.maximumRPM, minimum < maximum else { return nil }
            return (fan.index, minimum + (maximum - minimum) * normalized)
        })
    }
}
