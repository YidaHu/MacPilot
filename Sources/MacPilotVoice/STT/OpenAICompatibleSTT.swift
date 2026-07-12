@preconcurrency import Foundation

public enum STTPreset: String, CaseIterable, Sendable {
    case glmASR
    case openAIWhisper
    case groqWhisper
    case siliconFlow
}

public enum STTClientError: Error, Equatable {
    case invalidConfiguration(String)
    case apiKeyRequired
    case unauthorized
    case rateLimited
    case timeout
    case httpStatus(Int)
    case malformedResponse
    case emptyTranscript
}

public struct STTProviderConfiguration: Equatable, Sendable {
    public let name: String
    public let endpoint: URL
    public let model: String
    public let extraFields: [String: String]
    public let apiKeyRequired: Bool
    public let maximumDuration: TimeInterval?

    public static func preset(_ preset: STTPreset) throws -> STTProviderConfiguration {
        switch preset {
        case .glmASR:
            return try known(name: "glm-asr", endpoint: "https://open.bigmodel.cn/api/paas/v4/audio/transcriptions", model: "glm-asr-2512", extraFields: ["stream": "false"], maximumDuration: 28)
        case .openAIWhisper:
            return try known(name: "openai-whisper", endpoint: "https://api.openai.com/v1/audio/transcriptions", model: "whisper-1")
        case .groqWhisper:
            return try known(name: "groq-whisper", endpoint: "https://api.groq.com/openai/v1/audio/transcriptions", model: "whisper-large-v3-turbo")
        case .siliconFlow:
            return try known(name: "siliconflow", endpoint: "https://api.siliconflow.cn/v1/audio/transcriptions", model: "FunAudioLLM/SenseVoiceSmall")
        }
    }

    public static func customWhisper(baseURL: String, model: String) throws -> STTProviderConfiguration {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: trimmed), ["http", "https"].contains(components.scheme?.lowercased()) else {
            throw STTClientError.invalidConfiguration("Base URL must start with http:// or https://")
        }
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanModel.isEmpty else { throw STTClientError.invalidConfiguration("Model is required") }
        if !components.path.hasSuffix("/audio/transcriptions") {
            components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.path = "/" + [components.path, "audio/transcriptions"].filter { !$0.isEmpty && $0 != "/" }.joined(separator: "/")
        }
        guard let endpoint = components.url else { throw STTClientError.invalidConfiguration("Invalid endpoint") }
        return STTProviderConfiguration(name: "custom-whisper", endpoint: endpoint, model: cleanModel, extraFields: [:], apiKeyRequired: false, maximumDuration: nil)
    }

    private static func known(
        name: String,
        endpoint: String,
        model: String,
        extraFields: [String: String] = [:],
        maximumDuration: TimeInterval? = nil
    ) throws -> STTProviderConfiguration {
        guard let url = URL(string: endpoint) else { throw STTClientError.invalidConfiguration(endpoint) }
        return STTProviderConfiguration(name: name, endpoint: url, model: model, extraFields: extraFields, apiKeyRequired: true, maximumDuration: maximumDuration)
    }
}

public final class OpenAICompatibleSTT: @unchecked Sendable, Transcribing {
    private let configuration: STTProviderConfiguration
    private let apiKey: String
    private let language: String?
    private let session: URLSession

    public init(configuration: STTProviderConfiguration, apiKey: String = "", language: String? = nil, session: URLSession = .shared) {
        self.configuration = configuration
        self.apiKey = apiKey
        self.language = language
        self.session = session
    }

    public func transcribe(_ audio: RecordedAudio) async throws -> String {
        if configuration.apiKeyRequired && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw STTClientError.apiKeyRequired
        }
        if let maximumDuration = configuration.maximumDuration, audio.duration > maximumDuration {
            throw STTClientError.invalidConfiguration("Recording exceeds provider duration limit")
        }

        let boundary = "MacPilot-\(UUID().uuidString)"
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = min(max(60, audio.duration + 60), 300)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        request.httpBody = multipartBody(audio: audio, boundary: boundary)

        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch let error as URLError where error.code == .timedOut { throw STTClientError.timeout }
        catch { throw error }

        guard let http = response as? HTTPURLResponse else { throw STTClientError.malformedResponse }
        switch http.statusCode {
        case 200..<300: break
        case 401: throw STTClientError.unauthorized
        case 429: throw STTClientError.rateLimited
        default: throw STTClientError.httpStatus(http.statusCode)
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let text = object["text"] as? String else {
            throw STTClientError.malformedResponse
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw STTClientError.emptyTranscript }
        return trimmed
    }

    private func multipartBody(audio: RecordedAudio, boundary: String) -> Data {
        var data = Data()
        func append(_ string: String) { data.append(Data(string.utf8)) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        field("model", configuration.model)
        if let language, !language.isEmpty, language != "multi" { field("language", language) }
        for (name, value) in configuration.extraFields.sorted(by: { $0.key < $1.key }) { field(name, value) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        data.append(audio.wavData)
        append("\r\n--\(boundary)--\r\n")
        return data
    }
}
