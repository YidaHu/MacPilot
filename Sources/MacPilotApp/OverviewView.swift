import MacPilotCalendar
import MacPilotCore
import MacPilotFan
import MacPilotSystemActions
import SwiftUI

struct OverviewView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var calendar: CalendarReminderController
    @ObservedObject var fans: FanStore
    @ObservedObject var tools: SystemToolsStore
    let cleaning: CleaningOverlayController
    @State private var shortcutError: String?
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 9) {
                healthBanner
                if let snapshot = store.snapshot {
                    LazyVGrid(columns: columns, spacing: 8) {
                        MetricCard(title: "CPU", value: percent(snapshot.cpuUsage), detail: "实时使用率", progress: snapshot.cpuUsage)
                        MetricCard(
                            title: "内存",
                            value: bytes(snapshot.memory.usedBytes),
                            detail: "共 \(bytes(snapshot.memory.totalBytes))",
                            progress: ratio(snapshot.memory.usedBytes, snapshot.memory.totalBytes)
                        )
                        MetricCard(
                            title: "磁盘",
                            value: bytes(snapshot.disk.availableBytes),
                            detail: "可用，共 \(bytes(snapshot.disk.totalBytes))",
                            progress: 1 - ratio(snapshot.disk.availableBytes, snapshot.disk.totalBytes)
                        )
                        MetricCard(
                            title: "网络",
                            value: "↓ \(rate(snapshot.network.downloadBytesPerSecond))",
                            detail: "↑ \(rate(snapshot.network.uploadBytesPerSecond)) · \(snapshot.network.interfaceName ?? "未连接")",
                            progress: nil
                        )
                    }
                    HStack(spacing: 8) {
                        FanPreviewCard(title: "左风扇", fan: fans.snapshot?.fans.first(where: { $0.index == 0 }))
                        FanPreviewCard(title: "右风扇", fan: fans.snapshot?.fans.first(where: { $0.index == 1 }))
                    }
                    shortcutRow
                    voiceCard
                    Text("更新于 \(snapshot.sampledAt.formatted(date: .omitted, time: .standard))")
                        .font(.caption2)
                        .foregroundColor(snapshot.isStale(threshold: 20) ? .orange : .secondary)
                } else {
                    ProgressView("正在读取系统状态…")
                        .frame(maxWidth: .infinity, minHeight: 300)
                }
            }
        }
    }

    private var healthBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.lastErrorDescription == nil ? "系统运行良好" : "部分指标暂不可用")
                    .font(.subheadline.weight(.semibold))
                Text(store.snapshot?.network.riskExplanation ?? "正在建立系统快照")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(riskLabel)
                .font(.caption.weight(.semibold))
                .foregroundColor(riskColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(riskColor.opacity(0.13))
                .clipShape(Capsule())
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private var shortcutRow: some View {
        HStack(spacing: 7) {
            ToolShortcut(icon: "bolt.fill", title: "省电", isEnabled: tools.state(for: .lowPower) == .enabled) {
                Task { await tools.toggle(.lowPower) }
            }
            ToolShortcut(icon: "cup.and.saucer.fill", title: "唤醒", isEnabled: tools.state(for: .keepAwake) == .enabled) {
                Task { await tools.toggle(.keepAwake) }
            }
            RocketShortcut(isEnabled: calendar.isEnabled) { calendar.setEnabled(!calendar.isEnabled) }
            ToolShortcut(icon: "keyboard", title: "键盘", isEnabled: false) {
                do { try cleaning.showKeyboardCleaning() }
                catch { shortcutError = error.localizedDescription }
            }
        }
        .help(shortcutError ?? "快捷工具")
    }

    private var voiceCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("OpenTypeless").font(.subheadline.weight(.semibold))
                Text("语音迁移阶段启用").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "mic.fill")
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color.indigo)
                .clipShape(Circle())
        }
        .padding(11)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private var riskLabel: String {
        switch store.snapshot?.network.risk {
        case .normal: return "连接正常"
        case .attention: return "需要注意"
        case .unknown, .none: return "检查中"
        }
    }

    private var riskColor: Color {
        switch store.snapshot?.network.risk {
        case .normal: return .green
        case .attention: return .orange
        case .unknown, .none: return .secondary
        }
    }

    private func ratio(_ value: UInt64, _ total: UInt64) -> Double {
        guard total > 0 else { return 0 }
        return min(max(Double(value) / Double(total), 0), 1)
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    private func bytes(_ value: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory) }
    private func rate(_ value: UInt64) -> String { "\(ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file))/s" }
}

private struct RocketShortcut: View {
    let isEnabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Text("🚀").font(.body)
                Text("会议").font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(isEnabled ? Color.indigo : Color(nsColor: .controlBackgroundColor).opacity(0.88))
            .foregroundColor(isEnabled ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
            Text(detail).font(.caption2).foregroundColor(.secondary).lineLimit(1)
            if let progress {
                ProgressView(value: progress).progressViewStyle(.linear)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 91, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }
}

private struct FanPreviewCard: View {
    let title: String
    let fan: FanStatus?
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text(title); Spacer(); Text(fan.map { "\(Int($0.actualRPM)) RPM" } ?? "— RPM").fontWeight(.semibold) }
            ProgressView(value: progress).tint(.cyan)
            Text(fan == nil ? "正在读取 SMC" : "系统自动 · 点击风扇页调节").font(.caption2).foregroundColor(.secondary)
        }
        .padding(11)
        .foregroundColor(.white)
        .background(Color(red: 0.11, green: 0.16, blue: 0.25))
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private var progress: Double {
        guard let fan, let minimum = fan.minimumRPM, let maximum = fan.maximumRPM, maximum > minimum else { return 0 }
        return min(max((fan.actualRPM - minimum) / (maximum - minimum), 0), 1)
    }
}

private struct ToolShortcut: View {
    let icon: String
    let title: String
    let isEnabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.body)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(isEnabled ? Color.accentColor : Color(nsColor: .controlBackgroundColor).opacity(0.88))
            .foregroundColor(isEnabled ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }
}
