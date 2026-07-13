import AppKit
import Foundation
import MacPilotCore
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
    @Published private(set) var capsuleState: CapsuleDisplayState = .idle
    @Published private(set) var pendingOutputText: String?
    @Published private(set) var errorSettingsSection: SettingsSection = .voice

    @Published var isEnabled: Bool
    @Published var sttProvider: String
    @Published var sttLanguage: String
    @Published var sttCustomBaseURL: String
    @Published var sttCustomModel: String
    @Published var llmProvider: String
    @Published var llmBaseURL: String
    @Published var llmModel: String
    @Published private(set) var hotkeyCandidate: HotKeyDescriptor
    @Published private(set) var hotkeySaveError: String?
    @Published var hotkeyMode: String
    @Published var polishEnabled: Bool
    @Published var capsuleAutoHide: Bool
    @Published var structuredDictationEnabled: Bool
    @Published var structuredDictationPrompt: String

    private let defaults: UserDefaults
    private let keychain: KeychainStore
    private var persistentStore: VoicePersistentStore?
    private var sttAPIKey = ""
    private var llmAPIKey = ""
    private var pipeline: VoicePipeline?
    private var hotKeyController: GlobalHotKeyController?
    private var presentationAdapter = VoicePresentationAdapter()
    private var recordingStartedAt: Date?
    private var recordingTimer: Task<Void, Never>?
    private var completionTask: Task<Void, Never>?
    private var operationTask: Task<Void, Never>?
    private var errorCollapseTask: Task<Void, Never>?
    private var processingWarning: VoicePipelineWarning?
    private var lastProcessedText: String?
    @Published private var savedHotkey: HotKeyDescriptor
    private var savedHotkeyMode: String

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
        let storedHotkey = HotKeyDescriptor.resolve(defaults.string(forKey: Keys.hotkey))
        let storedHotkeyMode = HotKeyMode(rawValue: defaults.string(forKey: Keys.hotkeyMode) ?? "")?.rawValue ?? "toggle"
        hotkeyCandidate = storedHotkey
        hotkeySaveError = nil
        hotkeyMode = storedHotkeyMode
        savedHotkey = storedHotkey
        savedHotkeyMode = storedHotkeyMode
        polishEnabled = defaults.object(forKey: Keys.polishEnabled) as? Bool ?? true
        capsuleAutoHide = defaults.object(forKey: Keys.capsuleAutoHide) as? Bool ?? true
        structuredDictationEnabled = defaults.object(forKey: Keys.structuredEnabled) as? Bool ?? false
        structuredDictationPrompt = defaults.string(forKey: Keys.structuredPrompt) ?? StructuredDictationSettings.defaultPrompt

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
        case .structured: return "正在结构化口述…"
        case .outputting: return "正在写入当前输入框…"
        }
    }

    var canRecord: Bool { isEnabled && pipeline != nil && (stage == .idle || stage == .recording) }
    var capsuleSize: CapsuleSize { CapsuleLayout.size(for: capsuleState) }
    var hotkey: String { savedHotkey.displayValue }

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

    func setCapsuleAutoHide(_ autoHide: Bool) {
        capsuleAutoHide = autoHide
        defaults.set(autoHide, forKey: Keys.capsuleAutoHide)
    }

    func setStructuredDictationEnabled(_ enabled: Bool) {
        structuredDictationEnabled = enabled
        if enabled { polishEnabled = true }
        defaults.set(enabled, forKey: Keys.structuredEnabled)
        defaults.set(polishEnabled, forKey: Keys.polishEnabled)
        rebuildRuntime()
    }

    func setPolishEnabled(_ enabled: Bool) {
        polishEnabled = enabled
        if !enabled { structuredDictationEnabled = false }
        defaults.set(polishEnabled, forKey: Keys.polishEnabled)
        defaults.set(structuredDictationEnabled, forKey: Keys.structuredEnabled)
        rebuildRuntime()
    }

    func resetStructuredPrompt() {
        structuredDictationPrompt = StructuredDictationSettings.defaultPrompt
    }

    func setHotKeyCandidate(_ descriptor: HotKeyDescriptor) {
        hotkeyCandidate = descriptor
        hotkeySaveError = nil
    }

    func setHotKeyCaptureActive(_ active: Bool) {
        guard isEnabled, let controller = hotKeyController else { return }
        if active {
            controller.unregister()
            return
        }
        do {
            try controller.register(savedHotkey)
            hotkeySaveError = nil
        } catch {
            hotkeySaveError = "无法恢复当前快捷键，请重新保存快捷键。"
        }
    }

    func saveHotKeyConfiguration() {
        let candidate = hotkeyCandidate
        let mode = HotKeyMode(rawValue: hotkeyMode) ?? .toggle

        guard isEnabled else {
            commitHotKey(candidate, mode: mode)
            return
        }

        let previousController = hotKeyController
        previousController?.unregister()
        let replacement = GlobalHotKeyController(mode: mode) { [weak self] action in self?.perform(action) }
        do {
            try replacement.register(candidate)
            hotKeyController = replacement
            commitHotKey(candidate, mode: mode)
        } catch {
            try? previousController?.register(savedHotkey)
            hotKeyController = previousController
            hotkeyCandidate = savedHotkey
            hotkeyMode = savedHotkeyMode
            hotkeySaveError = "快捷键已被占用或无法注册。原快捷键仍然有效。"
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
        defaults.set(polishEnabled, forKey: Keys.polishEnabled)
        let structured = StructuredDictationSettings(enabled: structuredDictationEnabled, prompt: structuredDictationPrompt)
        structuredDictationPrompt = structured.prompt
        defaults.set(structured.enabled, forKey: Keys.structuredEnabled)
        defaults.set(structured.prompt, forKey: Keys.structuredPrompt)
        errorMessage = nil
        reloadKeysAndRebuild()
    }

    func saveSTTKey(_ value: String) {
        saveKey(value, account: "stt.\(sttProvider)")
    }

    func saveLLMKey(_ value: String) {
        saveKey(value, account: "llm.\(llmProvider)")
    }

    func clearError() {
        errorMessage = nil
        errorCollapseTask?.cancel()
        if stage == .idle {
            presentationAdapter.resetToIdle()
            capsuleState = presentationAdapter.displayState
        }
    }

    func copyPendingOutput() {
        guard let pendingOutputText else { return }
        NSPasteboard.general.clearContents()
        _ = NSPasteboard.general.setString(pendingOutputText, forType: .string)
    }

    func retryPendingOutput() {
        guard let pendingOutputText else { return }
        Task { [weak self] in
            guard let store = self else { return }
            do {
                try await AccessibleTextOutput().output(pendingOutputText)
                store.pendingOutputText = nil
                store.clearError()
            } catch {
                store.showCapsuleError(store.describe(error), section: store.settingsSection(for: error))
            }
        }
    }

    func cancelCurrentOperation() {
        operationTask?.cancel()
        operationTask = nil
        hotKeyController?.resetInteraction()
        Task { [weak self] in
            guard let store = self else { return }
            await store.pipeline?.abort()
            store.presentationAdapter.resetToIdle()
            store.capsuleState = store.presentationAdapter.displayState
            store.stopRecordingTimer()
        }
    }

    func copyHistory(_ entry: VoiceHistoryEntry) {
        NSPasteboard.general.clearContents()
        _ = NSPasteboard.general.setString(entry.polishedText, forType: .string)
    }

    func pasteHistory(_ entry: VoiceHistoryEntry) {
        guard stage == .idle else { return }
        Task {
            do { try await AccessibleTextOutput().output(entry.polishedText) }
            catch { errorMessage = describe(error) }
        }
    }

    func repolishHistory(_ entry: VoiceHistoryEntry) {
        guard stage == .idle, let persistentStore else { return }
        do {
            let polisher = try makePolisher()
            stage = .polishing
            errorMessage = nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let polished = try await polisher.polish(entry.rawText, context: VoiceContext())
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !polished.isEmpty else { throw VoicePipelineError.emptyTranscript }
                    try persistentStore.updateHistory(id: entry.id, polishedText: polished)
                    self.reloadHistory()
                } catch { self.errorMessage = self.describe(error) }
                self.stage = .idle
            }
        } catch { errorMessage = describe(error) }
    }

    func deleteHistory(_ entry: VoiceHistoryEntry) {
        guard let persistentStore else { return }
        do {
            try persistentStore.deleteHistory(id: entry.id)
            reloadHistory()
        } catch { errorMessage = "删除历史记录失败：\(error.localizedDescription)" }
    }

    func shutdown() {
        hotKeyController?.unregister()
        recordingTimer?.cancel()
        completionTask?.cancel()
        errorCollapseTask?.cancel()
        operationTask?.cancel()
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
                configuration: .init(
                    polishEnabled: polishEnabled,
                    structuredDictation: .init(
                        enabled: structuredDictationEnabled,
                        prompt: structuredDictationPrompt
                    )
                ),
                onTransition: { [weak self] state in
                    Task { @MainActor [weak self] in
                        self?.handleTransition(state)
                    }
                },
                onWarning: { [weak self] warning in
                    Task { @MainActor [weak self] in self?.processingWarning = warning }
                }
            )
            let mode = HotKeyMode(rawValue: savedHotkeyMode) ?? .toggle
            let controller = GlobalHotKeyController(mode: mode) { [weak self] action in self?.perform(action) }
            if isEnabled { try controller.register(savedHotkey) }
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
        operationTask?.cancel()
        operationTask = Task { [weak self] in
            guard let store = self else { return }
            do {
                switch action {
                case .startRecording: _ = try await pipeline.startRecording()
                case .stopRecording:
                    try await pipeline.stopRecording()
                    store.reloadHistory()
                case .none: break
                }
            } catch {
                store.hotKeyController?.resetInteraction()
                let message = store.describe(error)
                if error as? AccessibleTextOutputError == .accessibilityPermissionRequired {
                    store.pendingOutputText = store.lastProcessedText
                }
                store.showCapsuleError(message, section: store.settingsSection(for: error))
            }
            store.operationTask = nil
        }
    }

    private func handleTransition(_ state: VoicePipelineState) {
        stage = state.stage
        capsuleState = presentationAdapter.consume(state)
        if state.stage == .outputting { lastProcessedText = state.outputText }
        if state.stage == .recording {
            if recordingStartedAt == nil { recordingStartedAt = Date() }
            startRecordingTimer()
        } else {
            stopRecordingTimer()
        }
        if state.stage == .idle {
            inputLevel = 0
            if let warning = processingWarning {
                processingWarning = nil
                let message: String
                switch warning {
                case .processingFallback(.structured): message = "结构化口述失败，已输出原始转录"
                case .processingFallback: message = "AI 润色失败，已输出原始转录"
                }
                errorSettingsSection = .artificialIntelligence
                errorMessage = message
                presentationAdapter.markFailed(message)
                capsuleState = presentationAdapter.displayState
                scheduleErrorCollapse()
            } else if capsuleState == .complete {
                completionTask?.cancel()
                completionTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    guard !Task.isCancelled, let store = self else { return }
                    store.presentationAdapter.resetToIdle()
                    store.capsuleState = store.presentationAdapter.displayState
                    store.lastProcessedText = nil
                }
            }
        }
    }

    private func startRecordingTimer() {
        guard recordingTimer == nil else { return }
        recordingTimer = Task { [weak self] in
            while !Task.isCancelled {
                guard let store = self, let started = store.recordingStartedAt else { return }
                store.presentationAdapter.updateRecording(level: store.inputLevel, elapsed: Date().timeIntervalSince(started))
                store.capsuleState = store.presentationAdapter.displayState
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.cancel()
        recordingTimer = nil
        recordingStartedAt = nil
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
        return OpenAICompatibleLLM(
            configuration: .init(endpoint: endpoint, model: llmModel, apiKey: llmAPIKey),
            promptOptions: .init(
                structuredDictationEnabled: structuredDictationEnabled,
                structuredDictationPrompt: structuredDictationPrompt
            )
        )
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
        Task { [weak self] in
            let result = await Task.detached { () -> Result<VoiceBootstrapData, Error> in
                Result {
                    let store = try VoicePersistentStore()
                    var summary: LegacyImportSummary?
                    var voiceUISettings: LegacyVoiceUISettings?
                    var migrationError: String?
                    if FileManager.default.fileExists(atPath: legacy.path) {
                        let importer = LegacyOpenTypelessImporter(store: store, keychain: keychain)
                        do { summary = try importer.importData(from: legacy) }
                        catch { migrationError = "OpenTypeless 数据迁移失败" }
                        do { voiceUISettings = try importer.importVoiceUISettings(from: legacy) }
                        catch { migrationError = "OpenTypeless 语音界面设置迁移失败" }
                    }
                    return VoiceBootstrapData(
                        store: store,
                        summary: summary,
                        voiceUISettings: voiceUISettings,
                        migrationError: migrationError,
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
                if let voiceUI = data.voiceUISettings {
                    if store.defaults.object(forKey: Keys.structuredEnabled) == nil {
                        store.structuredDictationEnabled = voiceUI.structuredDictationEnabled
                        store.defaults.set(store.structuredDictationEnabled, forKey: Keys.structuredEnabled)
                    }
                    if store.defaults.string(forKey: Keys.structuredPrompt) == nil {
                        store.structuredDictationPrompt = voiceUI.structuredDictationPrompt
                        store.defaults.set(store.structuredDictationPrompt, forKey: Keys.structuredPrompt)
                    }
                    if store.structuredDictationEnabled { store.polishEnabled = true }
                    store.defaults.set(store.polishEnabled, forKey: Keys.polishEnabled)
                }
                if let migrationError = data.migrationError { store.errorMessage = migrationError }
                store.refreshKeyStatus()
                store.rebuildRuntime()
                store.reloadKeysAndRebuild()
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
        savedHotkey = HotKeyDescriptor.resolve(settings.hotkey)
        hotkeyCandidate = savedHotkey
        savedHotkeyMode = HotKeyMode(rawValue: settings.hotkeyMode)?.rawValue ?? "toggle"
        hotkeyMode = savedHotkeyMode
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
        defaults.set(savedHotkey.storageValue, forKey: Keys.hotkey)
        defaults.set(savedHotkeyMode, forKey: Keys.hotkeyMode)
        defaults.set(polishEnabled, forKey: Keys.polishEnabled)
        defaults.set(structuredDictationEnabled, forKey: Keys.structuredEnabled)
        defaults.set(structuredDictationPrompt, forKey: Keys.structuredPrompt)
    }

    private func reloadHistory() {
        guard let persistentStore else { return }
        do { history = try persistentStore.history(limit: 20) }
        catch { errorMessage = "读取语音历史失败：\(error.localizedDescription)" }
    }

    private func commitHotKey(_ descriptor: HotKeyDescriptor, mode: HotKeyMode) {
        savedHotkey = descriptor
        savedHotkeyMode = mode.rawValue
        hotkeyCandidate = descriptor
        hotkeyMode = mode.rawValue
        defaults.set(descriptor.storageValue, forKey: Keys.hotkey)
        defaults.set(mode.rawValue, forKey: Keys.hotkeyMode)
        hotkeySaveError = nil
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

    private func showCapsuleError(_ message: String, section: SettingsSection = .voice) {
        errorMessage = message
        errorSettingsSection = section
        presentationAdapter.markFailed(message)
        capsuleState = presentationAdapter.displayState
        scheduleErrorCollapse()
    }

    private func scheduleErrorCollapse() {
        errorCollapseTask?.cancel()
        errorCollapseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let store = self else { return }
            store.presentationAdapter.collapseError()
            store.capsuleState = store.presentationAdapter.displayState
        }
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

    private func settingsSection(for error: Error) -> SettingsSection {
        switch error {
        case AudioCaptureError.microphonePermissionDenied,
             AccessibleTextOutputError.accessibilityPermissionRequired:
            return .permissions
        case is LLMClientError:
            return .artificialIntelligence
        default:
            return .voice
        }
    }
}

private struct VoiceBootstrapData: @unchecked Sendable {
    let store: VoicePersistentStore
    let summary: LegacyImportSummary?
    let voiceUISettings: LegacyVoiceUISettings?
    let migrationError: String?
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
    static let capsuleAutoHide = "voice.capsuleAutoHide"
    static let structuredEnabled = "voice.structuredDictationEnabled"
    static let structuredPrompt = "voice.structuredDictationPrompt"
}
