@preconcurrency import Foundation

public enum LLMClientError: Error, Equatable {
    case apiKeyRequired
    case unauthorized
    case rateLimited
    case timeout
    case httpStatus(Int)
    case malformedResponse
}

public struct LLMConfiguration: Equatable, Sendable {
    public let endpoint: URL
    public let model: String
    public let apiKey: String
    public let temperature: Double
    public let maximumTokens: Int

    public init(endpoint: URL, model: String, apiKey: String, temperature: Double = 0.3, maximumTokens: Int = 2_048) {
        self.endpoint = endpoint
        self.model = model
        self.apiKey = apiKey
        self.temperature = temperature
        self.maximumTokens = maximumTokens
    }
}

public final class OpenAICompatibleLLM: @unchecked Sendable, Polishing {
    private let configuration: LLMConfiguration
    private let promptOptions: PromptOptions
    private let session: URLSession

    public init(configuration: LLMConfiguration, promptOptions: PromptOptions = PromptOptions(), session: URLSession = .shared) {
        self.configuration = configuration
        self.promptOptions = promptOptions
        self.session = session
    }

    public func polish(_ rawText: String, context: VoiceContext) async throws -> String {
        guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMClientError.apiKeyRequired
        }
        let systemPrompt = PromptBuilder.build(promptOptions)
        var body: [String: Any] = [
            "model": configuration.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "<transcription>\n\(rawText)\n</transcription>"]
            ],
            "max_tokens": configuration.maximumTokens,
            "temperature": configuration.model.hasPrefix("glm-") ? max(configuration.temperature, 0.6) : configuration.temperature,
            "stream": false
        ]
        if configuration.model.hasPrefix("glm-") { body["thinking"] = ["type": "enabled"] }

        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch let error as URLError where error.code == .timedOut { throw LLMClientError.timeout }
        catch { throw error }

        guard let http = response as? HTTPURLResponse else { throw LLMClientError.malformedResponse }
        switch http.statusCode {
        case 200..<300: break
        case 401: throw LLMClientError.unauthorized
        case 429: throw LLMClientError.rateLimited
        default: throw LLMClientError.httpStatus(http.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMClientError.malformedResponse
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LLMClientError.malformedResponse }
        return trimmed
    }
}
