import MacPilotCalendar
import MacPilotCore
import SwiftUI

struct OverviewView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var calendar: CalendarReminderController
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
                        FanPreviewCard(title: "左风扇")
                        FanPreviewCard(title: "右风扇")
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
            ShortcutPreview(icon: "bolt.fill", title: "省电")
            ShortcutPreview(icon: "cup.and.saucer.fill", title: "唤醒")
            RocketShortcut(isEnabled: calendar.isEnabled) { calendar.setEnabled(!calendar.isEnabled) }
            ShortcutPreview(icon: "keyboard", title: "键盘")
        }
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
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text(title); Spacer(); Text("— RPM").fontWeight(.semibold) }
            Slider(value: .constant(0.35)).disabled(true)
            Text("风扇控制阶段启用").font(.caption2).foregroundColor(.secondary)
        }
        .padding(11)
        .foregroundColor(.white)
        .background(Color(red: 0.11, green: 0.16, blue: 0.25))
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }
}

private struct ShortcutPreview: View {
    let icon: String
    let title: String
    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.body)
            Text(title).font(.caption2)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .opacity(0.65)
    }
}
