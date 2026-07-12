public enum SystemToolID: String, CaseIterable, Identifiable, Sendable {
    case lowPower
    case keepAwake
    case lockScreen
    case keepDisplayAwake
    case cleanScreen
    case cleanKeyboard
    case darkMode
    case desktopFiles
    case dockVisibility
    case emptyTrash
    case rocketReminder

    public var id: String { rawValue }
}

public enum SystemToolState: Equatable, Sendable {
    case unknown
    case enabled
    case disabled
}
