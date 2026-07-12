import SwiftUI

struct VoicePlaceholderView: View {
    var body: some View {
        PlaceholderPage(
            icon: "waveform.and.mic",
            title: "OpenTypeless",
            message: "语音迁移阶段将启用录音、转写、AI 润色、自动粘贴和历史记录。"
        )
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
