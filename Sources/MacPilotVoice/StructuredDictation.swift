import Foundation

public struct StructuredDictationSettings: Equatable, Sendable {
    public static let defaultPrompt = """
    Preserve the speaker's meaning and language. For long or multi-topic dictation, organize the text with a concise factual title, clear sections, natural paragraphs, and numbered points only when useful. Never add information that was not spoken. Short single-topic dictation should remain natural prose without forced headings.
    """

    public let enabled: Bool
    public let prompt: String

    public static let disabled = StructuredDictationSettings(enabled: false, prompt: defaultPrompt)

    public init(enabled: Bool, prompt: String = defaultPrompt) {
        self.enabled = enabled
        let sanitized = String(
            prompt.replacingOccurrences(of: "\0", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(2_000)
        )
        self.prompt = sanitized.isEmpty ? Self.defaultPrompt : sanitized
    }
}

public struct VoiceProcessingSettings: Equatable, Sendable {
    public var polishEnabled: Bool
    public var structuredDictation: StructuredDictationSettings

    public init(polishEnabled: Bool, structuredDictation: StructuredDictationSettings) {
        self.polishEnabled = polishEnabled
        self.structuredDictation = structuredDictation
    }

    public mutating func setStructuredEnabled(_ enabled: Bool) {
        if enabled { polishEnabled = true }
        structuredDictation = .init(enabled: enabled, prompt: structuredDictation.prompt)
    }
}
