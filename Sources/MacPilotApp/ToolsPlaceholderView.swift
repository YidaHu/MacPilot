import MacPilotCalendar
import SwiftUI

struct ToolsView: View {
    @ObservedObject var calendar: CalendarReminderController
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    private let tools = [
        ("bolt.fill", "省电模式"), ("cup.and.saucer.fill", "保持唤醒"), ("lock.fill", "锁屏"),
        ("sun.max.fill", "保持亮屏"), ("display", "清洁屏幕"), ("keyboard", "清洁键盘"),
        ("circle.lefthalf.filled", "深色模式"), ("eye", "桌面文件"), ("dock.rectangle", "程序坞"),
        ("trash", "清倒废纸篓")
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 9) {
                ForEach(Array(tools.enumerated()), id: \.offset) { _, tool in
                    toolCard(icon: tool.0, title: tool.1)
                }
                Button { calendar.setEnabled(!calendar.isEnabled) } label: {
                    VStack(spacing: 7) {
                        Text("🚀").font(.title2)
                        Text("会议火箭").font(.caption.weight(.medium))
                        Text(calendar.isEnabled ? "已开启" : "已关闭").font(.caption2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .background(calendar.isEnabled ? Color.indigo : Color(nsColor: .controlBackgroundColor))
                    .foregroundColor(calendar.isEnabled ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
            Text("系统工具将在本阶段继续接入；会议火箭已可控制。")
                .font(.caption).foregroundColor(.secondary).padding(.top, 12)
        }
    }

    private func toolCard(icon: String, title: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon).font(.title3)
            Text(title).font(.caption.weight(.medium))
            Text("即将启用").font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(0.7)
    }
}
