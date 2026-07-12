import MacPilotVoice
import SwiftUI

struct FloatingVoiceCapsuleView: View {
    @ObservedObject var store: VoiceStore
    let onDrag: (CGSize, Bool) -> Void
    let openSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .frame(width: store.capsuleSize.width, height: store.capsuleSize.height)
            .background(background)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.7))
            .shadow(color: shadowColor, radius: 13, y: 7)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { onDrag($0.translation, false) }
                    .onEnded { onDrag($0.translation, true) }
            )
            .padding(12)
    }

    @ViewBuilder private var content: some View {
        switch store.capsuleState {
        case .idle:
            Button { store.toggleRecording() } label: {
                Image(systemName: "mic.fill").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                    .scaleEffect(reduceMotion ? 1 : 1.02)
            }
            .buttonStyle(.plain)
            .help("开始语音输入")
        case let .recording(level, elapsed):
            HStack(spacing: 9) {
                Circle().fill(Color.white.opacity(0.9)).frame(width: 8, height: 8)
                VoiceLevelBars(level: level)
                Spacer(minLength: 4)
                Text(duration(elapsed)).font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.9))
                cancelButton(help: "取消录音")
            }
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onTapGesture { store.toggleRecording() }
        case .transcribing:
            processingRow(symbol: "arrow.triangle.2.circlepath", text: "转录中…", canCancel: true)
        case .polishing:
            processingRow(symbol: "ellipsis", text: "AI 润色中…", canCancel: true)
        case .structured:
            processingRow(symbol: "ellipsis", text: "结构化口述中…", canCancel: true)
        case .outputting:
            processingRow(symbol: "arrow.up.doc.fill", text: "正在写入…", canCancel: false)
        case .complete:
            Label("完成", systemImage: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
        case let .error(message, collapsed):
            Button(action: openSettings) {
                if collapsed {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.white)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(message).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func processingRow(symbol: String, text: String, canCancel: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .rotationEffect(symbol.contains("circlepath") && !reduceMotion ? .degrees(20) : .zero)
            Text(text).font(.system(size: 11, weight: .medium)).lineLimit(1)
            Spacer(minLength: 4)
            if canCancel { cancelButton(help: "取消当前处理") }
        }
        .foregroundColor(.white.opacity(0.92))
        .padding(.horizontal, 12)
    }

    private func cancelButton(help: String) -> some View {
        Button { store.cancelCurrentOperation() } label: {
            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .foregroundColor(.white.opacity(0.75))
        .help(help)
    }

    private var background: some View {
        Group {
            switch store.capsuleState {
            case .recording:
                LinearGradient(colors: [Color(red: 1, green: 0.30, blue: 0.40), Color(red: 0.78, green: 0.12, blue: 0.27)], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .complete:
                LinearGradient(colors: [.green.opacity(0.9), .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .error:
                LinearGradient(colors: [.orange, .red.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .idle:
                LinearGradient(colors: [Color(nsColor: .darkGray), .black.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)
            default:
                LinearGradient(colors: [Color(red: 0.42, green: 0.35, blue: 1), Color(red: 0.24, green: 0.17, blue: 0.77)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }

    private var shadowColor: Color {
        switch store.capsuleState {
        case .recording: return .red.opacity(0.32)
        case .error: return .orange.opacity(0.3)
        default: return .indigo.opacity(0.28)
        }
    }

    private func duration(_ interval: TimeInterval) -> String {
        let seconds = max(Int(interval), 0)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct VoiceLevelBars: View {
    let level: Float
    private let weights: [CGFloat] = [0.55, 0.85, 1, 0.68, 0.9, 0.5, 0.72]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(weights.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(0.82))
                    .frame(width: 2, height: 3 + 13 * max(CGFloat(level) * weights[index], 0.12))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
        .frame(height: 18)
    }
}
