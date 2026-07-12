import MacPilotFan
import SwiftUI

struct FansView: View {
    @ObservedObject var store: FanStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                presetPicker
                if let snapshot = store.snapshot {
                    ForEach(snapshot.fans) { fan in
                        FanControlCard(fan: fan, store: store)
                    }
                } else {
                    ProgressView("正在读取 Apple SMC…").frame(maxWidth: .infinity, minHeight: 220)
                }
                safetyStatus
            }
        }
    }

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("控制模式").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105))], spacing: 7) {
                ForEach(FanPreset.allCases) { preset in
                    Button {
                        Task { await store.applyPreset(preset) }
                    } label: {
                        Text(preset.title)
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(store.selectedPreset == preset ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                            .foregroundColor(store.selectedPreset == preset ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private var safetyStatus: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: store.errorDescription == nil ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(store.errorDescription == nil ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.isInstallingHelper ? "正在请求管理员授权…" : "短租约安全保护")
                    .font(.caption.weight(.semibold))
                Text(store.errorDescription ?? "应用失联或租约超时后，助手会自动恢复系统控制。")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(10)
    }
}

private struct FanControlCard: View {
    let fan: FanStatus
    @ObservedObject var store: FanStore
    @State private var sliderValue: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: "fanblades").foregroundColor(.cyan)
                Text(fan.index == 0 ? "左风扇" : "右风扇").fontWeight(.semibold)
                Spacer()
                Text("\(Int(fan.actualRPM)) RPM").font(.title3.weight(.bold)).monospacedDigit()
            }
            Slider(
                value: Binding(get: { sliderValue == 0 ? currentTarget : sliderValue }, set: { sliderValue = $0 }),
                in: minimum...maximum,
                onEditingChanged: { editing in
                    guard !editing else { return }
                    let value = sliderValue == 0 ? currentTarget : sliderValue
                    Task { await store.setManualRPM(fanIndex: fan.index, rpm: value) }
                }
            )
            HStack {
                Text("最低 \(Int(minimum))")
                Spacer()
                Text("目标 \(Int(store.manualTargets[fan.index] ?? fan.targetRPM ?? fan.actualRPM))")
                Spacer()
                Text("最高 \(Int(maximum))")
            }
            .font(.caption2).foregroundColor(.secondary).monospacedDigit()
        }
        .padding(13)
        .foregroundColor(.white)
        .background(LinearGradient(colors: [Color(red: 0.08, green: 0.13, blue: 0.22), Color(red: 0.12, green: 0.25, blue: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear { sliderValue = currentTarget }
        .onChange(of: store.manualTargets[fan.index]) { value in if let value { sliderValue = value } }
    }

    private var minimum: Double { fan.minimumRPM ?? 0 }
    private var maximum: Double { max(fan.maximumRPM ?? 1, minimum + 1) }
    private var currentTarget: Double { min(max(store.manualTargets[fan.index] ?? fan.targetRPM ?? fan.actualRPM, minimum), maximum) }
}
