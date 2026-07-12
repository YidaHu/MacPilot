import AppKit
import Foundation
import MacPilotVoice

@MainActor
final class VoiceStore: ObservableObject {
    @Published private(set) var stage: VoicePipelineStage = .idle
    @Published private(set) var inputLevel: Float = 0
    @Published private(set) var history: [VoiceHistoryEntry] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var migrationMessage = "未发现旧版数据"
    @Published private(set) var hasSTTKey = false
    @Published private(set) var hasLLMKey = false

    @Published var isEnabled: Bool
    @Published var sttProvider: String
    @Published var sttLanguage: String
    @Published var sttCustomBaseURL: String
    @Published var sttCustomModel: String
    @Published var llmProvider: String
    @Published var llmBaseURL: String
    @Published var llmModel: String
    @Published var hotkey: String
    @Published var hotkeyMode: String
    @Published var polishEnabled: Bool

    private let defaults: UserDefaults
    private let keychain: KeychainStore
    private var persistentStore: VoicePersistentStore?
    private var sttAPIKey = ""
    private var llmAPIKey = ""
    private var pipeline: VoicePipeline?
    private var hotKeyController: GlobalHotKeyController?

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        sttProvider = defaults.string(forKey: Keys.sttProvider) ?? "glm-asr"
        sttLanguage = defaults.string(forKey: Keys.sttLanguage) ?? "zh"
        sttCustomBaseURL = defaults.string(forKey: Keys.sttCustomBaseURL) ?? "http://127.0.0.1:8000/v1"
        sttCustomModel = defaults.string(forKey: Keys.sttCustomModel) ?? "Systran/faster-whisper-large-v3"
        llmProvider = defaults.string(forKey: Keys.llmProvider) ?? "zhipu"
        llmBaseURL = defaults.string(forKey: Keys.llmBaseURL) ?? "https://open.bigmodel.cn/api/paas/v4"
        llmModel = defaults.string(forKey: Keys.llmModel) ?? "glm-4-flash"
        hotkey = defaults.string(forKey: Keys.hotkey) ?? "Option+/"
        hotkeyMode = defaults.string(forKey: Keys.hotkeyMode) ?? "toggle"
        polishEnabled = defaults.object(forKey: Keys.polishEnabled) as? Bool ?? true

        persistentStore = nil
        bootstrap()
    }

    var stageTitle: String {
        switch stage {
        case .idle:
            if !isEnabled { return "语音功能已关闭" }
            return pipeline == nil && errorMessage == nil ? "正在准备语音服务…" : "准备就绪"
        case .recording: return "正在聆听…"
        case .transcribing: return "正在转写…"
        case .polishing: return "正在 AI 润色…"
        case .outputting: return "正在写入当前输入框…"
        }
    }

    var canRecord: Bool { isEnabled && pipeline != nil && (stage == .idle || stage == .recording) }

    func toggleRecording() {
        guard canRecord else { return }
        perform(stage == .recording ? .stopRecording : .startRecording)
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Keys.enabled)
        if enabled {
            rebuildRuntime()
        } else {
            hotKeyController?.unregister()
            Task { await pipeline?.abort() }
        }
    }

    func saveConfiguration() {
        defaults.set(sttProvider, forKey: Keys.sttProvider)
        defaults.set(sttLanguage, forKey: Keys.sttLanguage)
        defaults.set(sttCustomBaseURL, forKey: Keys.sttCustomBaseURL)
        defaults.set(sttCustomModel, forKey: Keys.sttCustomModel)
        defaults.set(llmProvider, forKey: Keys.llmProvider)
        defaults.set(llmBaseURL, forKey: Keys.llmBaseURL)
        defaults.set(llmModel, forKey: Keys.llmModel)
        defaults.set(hotkey, forKey: Keys.hotkey)
        defaults.set(hotkeyMode, forKey: Keys.hotkeyMode)
        defaults.set(polishEnabled, forKey: Keys.polishEnabled)
        errorMessage = nil
        reloadKeysAndRebuild()
    }

    func saveSTTKey(_ value: String) {
        saveKey(value, account: "stt.\(sttProvider)")
    }

    func saveLLMKey(_ value: String) {
        saveKey(value, account: "llm.\(llmProvider)")
    }

    func clearError() { errorMessage = nil }

    func shutdown() {
        hotKeyController?.unregister()
        Task { await pipeline?.abort() }
    }

    private func rebuildRuntime() {
        hotKeyController?.unregister()
        guard let persistentStore else { return }
        do {
            let sttConfig = try makeSTTConfiguration()
            let transcriber = OpenAICompatibleSTT(configuration: sttConfig, apiKey: sttAPIKey, language: sttLanguage)
            let polisher: any Polishing = try makePolisher()
            let maximumDuration = sttConfig.maximumDuration ?? 300
            let audio = AVAudioCapture(maximumDuration: maximumDuration) { [weak self] level in
                Task { @MainActor [weak self] in self?.inputLevel = min(max(level * 8, 0), 1) }
            }
            pipeline = VoicePipeline(
                audio: audio,
                transcriber: transcriber,
                polisher: polisher,
                output: AccessibleTextOutput(),
                history: persistentStore,
                onTransition: { [weak self] state in
                    Task { @MainActor [weak self] in
                        self?.stage = state.stage
                        if state.stage == .idle { self?.inputLevel = 0 }
                    }
                }
            )
            let mode = HotKeyMode(rawValue: hotkeyMode) ?? .toggle
            let controller = GlobalHotKeyController(mode: mode) { [weak self] action in self?.perform(action) }
            if isEnabled { try controller.register(HotKeyDescriptor.parse(hotkey)) }
            hotKeyController = controller
        } catch {
            pipeline = nil
            errorMessage = describe(error)
        }
        refreshKeyStatus()
    }

    private func perform(_ action: HotKeyAction) {
        guard isEnabled, let pipeline else { return }
        errorMessage = nil
        Task {
            do {
                switch action {
                case .startRecording: _ = try await pipeline.startRecording()
                case .stopRecording:
                    try await pipeline.stopRecording()
                    reloadHistory()
                case .none: break
                }
            } catch {
                hotKeyController?.resetInteraction()
                errorMessage = describe(error)
            }
        }
    }

    private func makeSTTConfiguration() throws -> STTProviderConfiguration {
        switch sttProvider {
        case "glm-asr": return try .preset(.glmASR)
        case "openai-whisper": return try .preset(.openAIWhisper)
        case "groq-whisper": return try .preset(.groqWhisper)
        case "siliconflow": return try .preset(.siliconFlow)
        case "custom-whisper": return try .customWhisper(baseURL: sttCustomBaseURL, model: sttCustomModel)
        default: throw STTClientError.invalidConfiguration("暂不支持该转写服务：\(sttProvider)")
        }
    }

    private func makePolisher() throws -> any Polishing {
        guard polishEnabled else { return PassthroughPolisher() }
        let endpoint = try completionEndpoint(baseURL: llmBaseURL)
        return OpenAICompatibleLLM(configuration: .init(endpoint: endpoint, model: llmModel, apiKey: llmAPIKey))
    }

    private func completionEndpoint(baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let value = trimmed.hasSuffix("chat/completions") ? trimmed : trimmed + "/chat/completions"
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased()) else {
            throw STTClientError.invalidConfiguration("AI 服务地址无效")
        }
        return url
    }

    private func bootstrap() {
        let legacy = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.opentypeless.app", isDirectory: true)
        let keychain = keychain
        let currentSTTProvider = sttProvider
        let currentLLMProvider = llmProvider
        Task { [weak self] in
            let result = await Task.detached { () -> Result<VoiceBootstrapData, Error> in
                Result {
                    let store = try VoicePersistentStore()
                    var summary: LegacyImportSummary?
                    var migrationError: String?
                    if FileManager.default.fileExists(atPath: legacy.path) {
                        do { summary = try LegacyOpenTypelessImporter(store: store, keychain: keychain).importData(from: legacy) }
                        catch { migrationError = "OpenTypeless 数据迁移失败" }
                    }
                    let sttProvider = summary.flatMap { $0.alreadyImported ? nil : $0.settings.sttProvider } ?? currentSTTProvider
                    let llmProvider = summary.flatMap { $0.alreadyImported ? nil : $0.settings.llmProvider } ?? currentLLMProvider
                    return VoiceBootstrapData(
                        store: store,
                        summary: summary,
                        migrationError: migrationError,
                        sttKey: try keychain.string(account: "stt.\(sttProvider)") ?? "",
                        llmKey: try keychain.string(account: "llm.\(llmProvider)") ?? "",
                        history: try store.history(limit: 20)
                    )
                }
            }.value
            guard let store = self else { return }
            switch result {
            case let .success(data):
                store.persistentStore = data.store
                store.history = data.history
                if let summary = data.summary {
                    if summary.alreadyImported {
                        store.migrationMessage = "OpenTypeless 数据已迁移"
                    } else {
                        store.apply(summary.settings)
                        store.saveConfigurationValues()
                        store.migrationMessage = "已迁移 \(summary.historyCount) 条历史记录、\(summary.dictionaryCount) 个词条"
                    }
                }
                if let migrationError = data.migrationError { store.errorMessage = migrationError }
                store.sttAPIKey = data.sttKey
                store.llmAPIKey = data.llmKey
                store.refreshKeyStatus()
                store.rebuildRuntime()
            case let .failure(error):
                store.errorMessage = "无法初始化语音服务：\(error.localizedDescription)"
            }
        }
    }

    private func apply(_ settings: ImportedVoiceSettings) {
        sttProvider = settings.sttProvider
        sttLanguage = settings.sttLanguage
        sttCustomBaseURL = settings.sttCustomBaseURL
        sttCustomModel = settings.sttCustomModel
        llmProvider = settings.llmProvider
        llmBaseURL = settings.llmBaseURL
        llmModel = settings.llmModel
        hotkey = settings.hotkey
        hotkeyMode = settings.hotkeyMode
        polishEnabled = settings.polishEnabled
    }

    private func saveConfigurationValues() {
        defaults.set(sttProvider, forKey: Keys.sttProvider)
        defaults.set(sttLanguage, forKey: Keys.sttLanguage)
        defaults.set(sttCustomBaseURL, forKey: Keys.sttCustomBaseURL)
        defaults.set(sttCustomModel, forKey: Keys.sttCustomModel)
        defaults.set(llmProvider, forKey: Keys.llmProvider)
        defaults.set(llmBaseURL, forKey: Keys.llmBaseURL)
        defaults.set(llmModel, forKey: Keys.llmModel)
        defaults.set(hotkey, forKey: Keys.hotkey)
        defaults.set(hotkeyMode, forKey: Keys.hotkeyMode)
        defaults.set(polishEnabled, forKey: Keys.polishEnabled)
    }

    private func reloadHistory() {
        guard let persistentStore else { return }
        do { history = try persistentStore.history(limit: 20) }
        catch { errorMessage = "读取语音历史失败：\(error.localizedDescription)" }
    }

    private func saveKey(_ value: String, account: String) {
        let keychain = keychain
        Task { [weak self] in
            let result = await Task.detached { () -> Result<Void, Error> in
                Result {
                    if value.isEmpty { try keychain.delete(account: account) }
                    else { try keychain.set(value, account: account) }
                }
            }.value
            guard let store = self else { return }
            switch result {
            case .success:
                if account == "stt.\(store.sttProvider)" { store.sttAPIKey = value }
                if account == "llm.\(store.llmProvider)" { store.llmAPIKey = value }
                store.refreshKeyStatus()
                store.errorMessage = nil
                store.rebuildRuntime()
            case let .failure(error): store.errorMessage = "保存密钥失败：\(error.localizedDescription)"
            }
        }
    }

    private func refreshKeyStatus() {
        hasSTTKey = !sttAPIKey.isEmpty
        hasLLMKey = !llmAPIKey.isEmpty
    }

    private func reloadKeysAndRebuild() {
        let keychain = keychain
        let sttAccount = "stt.\(sttProvider)"
        let llmAccount = "llm.\(llmProvider)"
        Task { [weak self] in
            let result = await Task.detached { () -> Result<(String, String), Error> in
                Result {
                    (try keychain.string(account: sttAccount) ?? "", try keychain.string(account: llmAccount) ?? "")
                }
            }.value
            guard let store = self else { return }
            switch result {
            case let .success((sttKey, llmKey)):
                store.sttAPIKey = sttKey
                store.llmAPIKey = llmKey
                store.refreshKeyStatus()
                store.rebuildRuntime()
            case let .failure(error): store.errorMessage = "读取钥匙串失败：\(error.localizedDescription)"
            }
        }
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case AudioCaptureError.microphonePermissionDenied: return "需要麦克风权限，请在系统设置的隐私与安全性中允许 MacPilot。"
        case AccessibleTextOutputError.accessibilityPermissionRequired: return "需要辅助功能权限，授权后才能把文字写入当前输入框。"
        case STTClientError.apiKeyRequired: return "请先在设置中填写转写服务 API Key。"
        case LLMClientError.apiKeyRequired: return "请先填写 AI 润色服务 API Key，或关闭 AI 润色。"
        case STTClientError.unauthorized, LLMClientError.unauthorized: return "API Key 无效或已过期。"
        case STTClientError.rateLimited, LLMClientError.rateLimited: return "服务请求过于频繁，请稍后再试。"
        case VoicePipelineError.emptyTranscript, STTClientError.emptyTranscript: return "没有识别到可用语音。"
        default: return error.localizedDescription
        }
    }
}

private struct VoiceBootstrapData: @unchecked Sendable {
    let store: VoicePersistentStore
    let summary: LegacyImportSummary?
    let migrationError: String?
    let sttKey: String
    let llmKey: String
    let history: [VoiceHistoryEntry]
}

private struct PassthroughPolisher: Polishing {
    func polish(_ rawText: String, context: VoiceContext) async throws -> String { rawText }
}

private enum Keys {
    static let enabled = "voice.enabled"
    static let sttProvider = "voice.sttProvider"
    static let sttLanguage = "voice.sttLanguage"
    static let sttCustomBaseURL = "voice.sttCustomBaseURL"
    static let sttCustomModel = "voice.sttCustomModel"
    static let llmProvider = "voice.llmProvider"
    static let llmBaseURL = "voice.llmBaseURL"
    static let llmModel = "voice.llmModel"
    static let hotkey = "voice.hotkey"
    static let hotkeyMode = "voice.hotkeyMode"
    static let polishEnabled = "voice.polishEnabled"
}
