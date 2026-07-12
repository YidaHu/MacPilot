import Foundation

public enum DashboardTab: String, CaseIterable, Identifiable, Sendable {
    case overview
    case fans
    case tools
    case voice

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: return "概览"
        case .fans: return "风扇"
        case .tools: return "工具"
        case .voice: return "语音"
        }
    }
}

public enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case general
    case appearance
    case monitoring
    case fans
    case tools
    case voice
    case artificialIntelligence
    case shortcuts
    case calendar
    case permissions
    case privacy
    case about

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return "通用"
        case .appearance: return "外观与菜单栏"
        case .monitoring: return "系统监控"
        case .fans: return "风扇与安全"
        case .tools: return "快捷工具"
        case .voice: return "语音与转写"
        case .artificialIntelligence: return "AI 润色与场景"
        case .shortcuts: return "快捷键"
        case .calendar: return "日历与提醒"
        case .permissions: return "权限"
        case .privacy: return "数据与隐私"
        case .about: return "关于"
        }
    }

    public var phaseDescription: String {
        switch self {
        case .general, .appearance, .monitoring: return "基础设置已开放"
        case .fans: return "将在风扇控制阶段开放"
        case .tools, .calendar: return "将在工具与提醒阶段开放"
        case .voice, .artificialIntelligence, .shortcuts, .permissions, .privacy:
            return "将在语音迁移阶段开放"
        case .about: return "MacPilot 0.1.0"
        }
    }
}

public enum RefreshPolicy {
    public static func interval(panelIsVisible: Bool) -> TimeInterval {
        panelIsVisible ? 1 : 15
    }
}
