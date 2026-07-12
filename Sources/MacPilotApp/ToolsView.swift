import MacPilotCalendar
import MacPilotCore
import MacPilotSystemActions
import SwiftUI

struct ToolsView: View {
    @ObservedObject var calendar: CalendarReminderController
    @ObservedObject var tools: SystemToolsStore
    let cleaning: CleaningOverlayController
    @State private var sessionError: String?
    @State private var confirmEmptyTrash = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    private let items: [(SystemToolID, String, String)] = [
        (.lowPower, "bolt.fill", "省电模式"), (.keepAwake, "cup.and.saucer.fill", "保持唤醒"), (.lockScreen, "lock.fill", "锁屏"),
        (.keepDisplayAwake, "sun.max.fill", "保持亮屏"), (.cleanScreen, "display", "清洁屏幕"), (.cleanKeyboard, "keyboard", "清洁键盘"),
        (.darkMode, "circle.lefthalf.filled", "深色模式"), (.desktopFiles, "eye.slash", "隐藏桌面"), (.dockVisibility, "dock.rectangle", "隐藏程序坞"),
        (.emptyTrash, "trash", "清倒废纸篓")
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 9) {
                ForEach(items, id: \.0) { tool, icon, title in
                    toolCard(tool: tool, icon: icon, title: title)
                }
                Button { calendar.setEnabled(!calendar.isEnabled) } label: {
                    cardContent(icon: nil, emoji: "🚀", title: "会议火箭", status: calendar.isEnabled ? "已开启" : "已关闭", enabled: calendar.isEnabled)
                }.buttonStyle(.plain)
            }
            if let error = sessionError ?? tools.errorDescription {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundColor(.orange).padding(.top, 10)
            } else {
                Text("可逆功能再次点击即可关闭；退出 MacPilot 会释放唤醒与亮屏断言。")
                    .font(.caption).foregroundColor(.secondary).padding(.top, 10)
            }
        }
        .confirmationDialog("确定清倒废纸篓？", isPresented: $confirmEmptyTrash) {
            Button("清倒废纸篓", role: .destructive) { Task { await tools.trigger(.emptyTrash) } }
            Button("取消", role: .cancel) {}
        }
    }

    private func toolCard(tool: SystemToolID, icon: String, title: String) -> some View {
        let enabled = tools.state(for: tool) == .enabled
        return Button { activate(tool) } label: {
            cardContent(icon: icon, emoji: nil, title: title, status: status(for: tool), enabled: enabled)
        }
        .buttonStyle(.plain)
        .disabled(tools.busyTool == tool)
    }

    private func cardContent(icon: String?, emoji: String?, title: String, status: String, enabled: Bool) -> some View {
        VStack(spacing: 7) {
            if let emoji { Text(emoji).font(.title2) }
            else if let icon { Image(systemName: icon).font(.title3) }
            Text(title).font(.caption.weight(.medium))
            Text(status).font(.caption2).foregroundColor(enabled ? .white.opacity(0.85) : .secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .background(enabled ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
        .foregroundColor(enabled ? .white : .primary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func activate(_ tool: SystemToolID) {
        sessionError = nil
        switch tool {
        case .cleanScreen: cleaning.showScreenCleaning()
        case .cleanKeyboard:
            do { try cleaning.showKeyboardCleaning() }
            catch { sessionError = error.localizedDescription }
        case .lockScreen: Task { await tools.trigger(tool) }
        case .emptyTrash: confirmEmptyTrash = true
        default: Task { await tools.toggle(tool) }
        }
    }

    private func status(for tool: SystemToolID) -> String {
        if tools.busyTool == tool { return "处理中…" }
        if tool == .lockScreen || tool == .emptyTrash || tool == .cleanScreen || tool == .cleanKeyboard { return "点击执行" }
        return tools.state(for: tool) == .enabled ? "已开启" : "已关闭"
    }
}
