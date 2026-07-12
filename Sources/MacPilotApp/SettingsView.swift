import AppKit
import MacPilotCalendar
import MacPilotCore
import MacPilotFan
import MacPilotSystemActions
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(calendar: CalendarReminderController, fans: FanStore, tools: SystemToolsStore, voice: VoiceStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacPilot 设置"
        window.minSize = NSSize(width: 680, height: 460)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView(calendar: calendar, fans: fans, tools: tools, voice: voice))
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        guard let window else { return }
        window.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var calendar: CalendarReminderController
    @ObservedObject var fans: FanStore
    @ObservedObject var tools: SystemToolsStore
    @ObservedObject var voice: VoiceStore
    @State private var selection: SettingsSection = .general
    @State private var sttKey = ""
    @State private var llmKey = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("MacPilot 设置")
                    .font(.headline)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        HStack {
                            Text(section.title)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(selection == section ? Color.accentColor.opacity(0.14) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(12)
            .frame(width: 190)
            .background(Color(nsColor: .underPageBackgroundColor))

            Divider()

            ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(selection.title).font(.title2.weight(.semibold))
                Text(selection.phaseDescription).foregroundColor(.secondary)
                if selection == .general {
                    SettingRow(title: "登录时启动", detail: "工具阶段开放登录项管理", control: "稍后开放")
                    SettingRow(title: "默认页面", detail: "点击菜单栏图标后显示", control: "概览")
                    SettingRow(title: "后台刷新", detail: "面板关闭后每 15 秒刷新", control: "已开启")
                } else if selection == .monitoring {
                    SettingRow(title: "面板刷新频率", detail: "面板打开时实时更新", control: "1 秒")
                    SettingRow(title: "后台刷新频率", detail: "降低常驻功耗", control: "15 秒")
                    SettingRow(title: "网络风险摘要", detail: "显示 VPN、代理和 Wi-Fi 加密依据", control: "已开启")
                } else if selection == .calendar {
                    SettingToggleRow(
                        title: "会议火箭提醒",
                        detail: "默认在会议开始前 10 分钟提醒",
                        isOn: Binding(get: { calendar.isEnabled }, set: { calendar.setEnabled($0) })
                    )
                    SettingRow(title: "提醒时间", detail: "当前使用已验证的默认策略", control: "提前 10 分钟")
                    SettingRow(title: "日历权限", detail: "关闭提醒不会撤销系统权限", control: calendar.status == .waitingForPermission ? "需要授权" : "正常")
                    Button("测试火箭") { calendar.testReminder() }
                } else if selection == .fans {
                    SettingRow(title: "控制模式", detail: "手动模式使用 5 秒短租约", control: fans.selectedPreset.title)
                    SettingRow(title: "硬件能力", detail: "只允许已验证的左右风扇范围", control: fans.snapshot?.controlsAvailable == true ? "双风扇可用" : "检查中")
                    SettingRow(title: "失联保护", detail: "助手断开、超时或应用退出后恢复", control: "系统自动")
                    Button("立即恢复系统自动控制") { Task { await fans.restoreAutomatic() } }
                } else if selection == .tools {
                    SettingRow(title: "保持唤醒", detail: "阻止系统空闲睡眠", control: tools.state(for: .keepAwake) == .enabled ? "已开启" : "已关闭")
                    SettingRow(title: "保持亮屏", detail: "阻止显示器空闲熄灭", control: tools.state(for: .keepDisplayAwake) == .enabled ? "已开启" : "已关闭")
                    SettingRow(title: "退出保护", detail: "退出应用时释放所有电源断言", control: "已开启")
                } else if selection == .voice {
                    SettingToggleRow(
                        title: "启用语音输入",
                        detail: "注册全局快捷键并允许录音、转写和自动粘贴",
                        isOn: Binding(get: { voice.isEnabled }, set: { voice.setEnabled($0) })
                    )
                    HStack {
                        Text("转写服务").fontWeight(.medium)
                        Spacer()
                        Picker("", selection: $voice.sttProvider) {
                            Text("智谱 GLM-ASR").tag("glm-asr")
                            Text("OpenAI Whisper").tag("openai-whisper")
                            Text("Groq Whisper").tag("groq-whisper")
                            Text("SiliconFlow").tag("siliconflow")
                            Text("Custom Whisper").tag("custom-whisper")
                        }.labelsHidden().frame(width: 190)
                    }
                    HStack {
                        Text("识别语言").fontWeight(.medium)
                        Spacer()
                        Picker("", selection: $voice.sttLanguage) {
                            Text("中文").tag("zh")
                            Text("英文").tag("en")
                            Text("自动识别").tag("multi")
                        }.labelsHidden().frame(width: 190)
                    }
                    if voice.sttProvider == "custom-whisper" {
                        LabeledTextField(title: "Whisper Base URL", value: $voice.sttCustomBaseURL, placeholder: "http://127.0.0.1:8000/v1")
                        LabeledTextField(title: "Whisper 模型", value: $voice.sttCustomModel, placeholder: "模型名称")
                    }
                    SecretSettingRow(title: "转写 API Key", isStored: voice.hasSTTKey, value: $sttKey) {
                        voice.saveSTTKey(sttKey); sttKey = ""
                    }
                    SettingRow(title: "旧版数据", detail: "只复制导入，不会修改 OpenTypeless 原目录", control: voice.migrationMessage)
                    Button("保存语音设置") { voice.saveConfiguration() }
                } else if selection == .artificialIntelligence {
                    SettingToggleRow(
                        title: "AI 润色",
                        detail: "转写完成后整理标点、语气和表达；关闭时直接输出原始转写",
                        isOn: $voice.polishEnabled
                    )
                    LabeledTextField(title: "服务标识", value: $voice.llmProvider, placeholder: "zhipu")
                    LabeledTextField(title: "API Base URL", value: $voice.llmBaseURL, placeholder: "https://…/v1")
                    LabeledTextField(title: "模型", value: $voice.llmModel, placeholder: "模型名称")
                    SecretSettingRow(title: "AI API Key", isStored: voice.hasLLMKey, value: $llmKey) {
                        voice.saveLLMKey(llmKey); llmKey = ""
                    }
                    Button("保存 AI 设置") { voice.saveConfiguration() }
                } else if selection == .shortcuts {
                    LabeledTextField(title: "语音快捷键", value: $voice.hotkey, placeholder: "Option+/")
                    HStack {
                        Text("触发方式").fontWeight(.medium)
                        Spacer()
                        Picker("", selection: $voice.hotkeyMode) {
                            Text("按一下开始／结束").tag("toggle")
                            Text("按住说话").tag("hold")
                        }.labelsHidden().frame(width: 190)
                    }
                    Text("支持 Option、Command、Control、Shift 与 /、.、Space、R 的组合。")
                        .font(.caption).foregroundColor(.secondary)
                    Button("保存快捷键") { voice.saveConfiguration() }
                } else if selection == .permissions {
                    SettingRow(title: "麦克风", detail: "录制语音所必需；首次录音时系统会请求", control: "按需授权")
                    SettingRow(title: "辅助功能", detail: "用于把结果粘贴到当前输入框", control: "按需授权")
                    HStack {
                        Button("打开麦克风权限") { openPrivacySettings("Privacy_Microphone") }
                        Button("打开辅助功能权限") { openPrivacySettings("Privacy_Accessibility") }
                    }
                } else if selection == .privacy {
                    SettingRow(title: "历史记录", detail: "保存在本机 MacPilot 应用支持目录", control: "仅本机")
                    SettingRow(title: "API Key", detail: "使用 macOS 钥匙串保存，不写入偏好文件", control: "钥匙串")
                    SettingRow(title: "网络请求", detail: "音频和文字只发送至你选择的转写与 AI 服务", control: "用户配置")
                } else {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            Image(systemName: "hammer.fill").font(.system(size: 34)).foregroundColor(.indigo)
                            Text(selection.phaseDescription).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func openPrivacySettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct LabeledTextField: View {
    let title: String
    @Binding var value: String
    let placeholder: String
    var body: some View {
        HStack {
            Text(title).fontWeight(.medium)
            Spacer()
            TextField(placeholder, text: $value).textFieldStyle(.roundedBorder).frame(width: 300)
        }
    }
}

private struct SecretSettingRow: View {
    let title: String
    let isStored: Bool
    @Binding var value: String
    let save: () -> Void
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(isStored ? "已安全保存在钥匙串" : "尚未设置").font(.caption).foregroundColor(isStored ? .green : .orange)
            }
            Spacer()
            SecureField(isStored ? "输入新值以替换" : "输入 API Key", text: $value)
                .textFieldStyle(.roundedBorder).frame(width: 220)
            Button("保存", action: save).disabled(value.isEmpty)
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.secondary.opacity(0.18)))
    }
}

private struct SettingToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden()
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.secondary.opacity(0.18)))
    }
}

private struct SettingRow: View {
    let title: String
    let detail: String
    let control: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text(control)
                .font(.caption)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.secondary.opacity(0.18)))
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }
}
