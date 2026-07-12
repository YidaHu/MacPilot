import SwiftUI

struct VoiceView: View {
    @ObservedObject var store: VoiceStore

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                statusCard
                if let error = store.errorMessage { errorCard(error) }
                historyCard
            }
        }
    }

    private var statusCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("OpenTypeless 语音").font(.headline)
                    Text(store.stageTitle).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { store.isEnabled }, set: { store.setEnabled($0) }))
                    .labelsHidden()
            }

            Button(action: { store.toggleRecording() }) {
                ZStack {
                    Circle().fill(store.stage == .recording ? Color.red : Color.indigo).frame(width: 76, height: 76)
                    Circle().stroke(Color.white.opacity(0.35), lineWidth: 5)
                        .frame(width: 58 + CGFloat(store.inputLevel) * 14, height: 58 + CGFloat(store.inputLevel) * 14)
                    Image(systemName: store.stage == .recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 27, weight: .semibold)).foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(!store.canRecord)

            Text(store.hotkeyMode == "hold" ? "按住 \(store.hotkey) 说话" : "按 \(store.hotkey) 开始／结束")
                .font(.caption).foregroundColor(.secondary)

            HStack(spacing: 8) {
                statusPill("转写", ready: store.hasSTTKey)
                statusPill("AI 润色", ready: !store.polishEnabled || store.hasLLMKey)
                statusPill("自动粘贴", ready: true)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func statusPill(_ title: String, ready: Bool) -> some View {
        Label(title, systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.caption2)
            .foregroundColor(ready ? .green : .orange)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(Capsule())
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text(message).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            Button { store.clearError() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("最近记录").font(.headline)
                Spacer()
                Text("\(store.history.count) 条").font(.caption).foregroundColor(.secondary)
            }
            if store.history.isEmpty {
                Text("完成一次语音输入后，文字会显示在这里。")
                    .font(.caption).foregroundColor(.secondary).padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(store.history.prefix(6)), id: \.id) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.polishedText).font(.callout).lineLimit(3)
                        HStack {
                            Text(item.createdAt, style: .relative).font(.caption2).foregroundColor(.secondary)
                            Spacer()
                            historyButton("doc.on.doc", help: "复制") { store.copyHistory(item) }
                            historyButton("arrow.up.doc", help: "重新粘贴") { store.pasteHistory(item) }
                            historyButton("wand.and.stars", help: "重新润色") { store.repolishHistory(item) }
                            historyButton("trash", help: "删除") { store.deleteHistory(item) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if item.id != store.history.prefix(6).last?.id { Divider() }
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func historyButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.caption) }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help(help)
    }
}

struct PlaceholderPage: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .medium))
                .foregroundColor(.indigo)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 290)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
