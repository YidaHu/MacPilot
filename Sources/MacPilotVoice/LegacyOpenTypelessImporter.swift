import Foundation
import SQLite3

public struct ImportedVoiceSettings: Equatable, Sendable {
    public let sttProvider: String
    public let sttLanguage: String
    public let sttCustomBaseURL: String
    public let sttCustomModel: String
    public let llmProvider: String
    public let llmBaseURL: String
    public let llmModel: String
    public let hotkey: String
    public let hotkeyMode: String
    public let polishEnabled: Bool
}

public struct LegacyImportSummary: Equatable, Sendable {
    public let historyCount: Int
    public let dictionaryCount: Int
    public let settings: ImportedVoiceSettings
    public let alreadyImported: Bool
}

public struct LegacyVoiceUISettings: Equatable, Sendable {
    public let structuredDictationEnabled: Bool
    public let structuredDictationPrompt: String
    public let alreadyImported: Bool
}

public enum LegacyImportError: Error {
    case missingSettings
    case corruptSettings
    case database(String)
}

public final class LegacyOpenTypelessImporter {
    public static let migrationVersion = "opentypeless-v1"
    public static let voiceUIMigrationVersion = "opentypeless-voice-ui-v2"
    private let store: VoicePersistentStore
    private let keychain: KeychainStore

    public init(store: VoicePersistentStore, keychain: KeychainStore = KeychainStore()) {
        self.store = store
        self.keychain = keychain
    }

    public func importData(from sourceDirectory: URL) throws -> LegacyImportSummary {
        if try store.hasMigration(version: Self.migrationVersion) {
            return LegacyImportSummary(historyCount: 0, dictionaryCount: 0, settings: emptySettings, alreadyImported: true)
        }
        let copied = try copyLegacyFiles(from: sourceDirectory)
        defer { try? FileManager.default.removeItem(at: copied.directory) }
        let parsed = try parseSettings(at: copied.settings)
        let records = try readDatabase(copied.database)

        var writtenAccounts: [String] = []
        do {
            if !parsed.sttKey.isEmpty {
                let account = "stt.\(parsed.settings.sttProvider)"
                try keychain.set(parsed.sttKey, account: account); writtenAccounts.append(account)
            }
            if !parsed.llmKey.isEmpty {
                let account = "llm.\(parsed.settings.llmProvider)"
                try keychain.set(parsed.llmKey, account: account); writtenAccounts.append(account)
            }
            try store.importLegacy(history: records.history, dictionary: records.dictionary, migrationVersion: Self.migrationVersion)
        } catch {
            writtenAccounts.forEach { try? keychain.delete(account: $0) }
            throw error
        }
        return LegacyImportSummary(historyCount: records.history.count, dictionaryCount: records.dictionary.count, settings: parsed.settings, alreadyImported: false)
    }

    public func importVoiceUISettings(from sourceDirectory: URL) throws -> LegacyVoiceUISettings {
        let alreadyImported = try store.hasMigration(version: Self.voiceUIMigrationVersion)
        let copied = try copySettingsFile(from: sourceDirectory)
        defer { try? FileManager.default.removeItem(at: copied.directory) }
        guard let root = try? JSONSerialization.jsonObject(with: Data(contentsOf: copied.settings)) as? [String: Any],
              let app = root["app_config"] as? [String: Any] else {
            throw LegacyImportError.corruptSettings
        }
        let rawPrompt = app["polish_custom_prompt"] as? String ?? ""
        let sanitized = StructuredDictationSettings(
            enabled: app["structured_dictation_enabled"] as? Bool ?? false,
            prompt: rawPrompt
        )
        if !alreadyImported {
            try store.recordMigration(version: Self.voiceUIMigrationVersion)
        }
        return LegacyVoiceUISettings(
            structuredDictationEnabled: sanitized.enabled,
            structuredDictationPrompt: sanitized.prompt,
            alreadyImported: alreadyImported
        )
    }

    private var emptySettings: ImportedVoiceSettings {
        ImportedVoiceSettings(sttProvider: "", sttLanguage: "", sttCustomBaseURL: "", sttCustomModel: "", llmProvider: "", llmBaseURL: "", llmModel: "", hotkey: "", hotkeyMode: "", polishEnabled: false)
    }

    private func copyLegacyFiles(from source: URL) throws -> (directory: URL, settings: URL, database: URL?) {
        let settings = source.appendingPathComponent("settings.json")
        guard FileManager.default.fileExists(atPath: settings.path) else { throw LegacyImportError.missingSettings }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacPilotLegacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let copiedSettings = directory.appendingPathComponent("settings.json")
        try FileManager.default.copyItem(at: settings, to: copiedSettings)
        let sourceDB = source.appendingPathComponent("opentypeless.db")
        var copiedDB: URL?
        if FileManager.default.fileExists(atPath: sourceDB.path) {
            let destination = directory.appendingPathComponent("opentypeless.db")
            try FileManager.default.copyItem(at: sourceDB, to: destination)
            for suffix in ["-wal", "-shm"] {
                let auxiliary = URL(fileURLWithPath: sourceDB.path + suffix)
                if FileManager.default.fileExists(atPath: auxiliary.path) {
                    try FileManager.default.copyItem(at: auxiliary, to: URL(fileURLWithPath: destination.path + suffix))
                }
            }
            copiedDB = destination
        }
        return (directory, copiedSettings, copiedDB)
    }

    private func copySettingsFile(from source: URL) throws -> (directory: URL, settings: URL) {
        let settings = source.appendingPathComponent("settings.json")
        guard FileManager.default.fileExists(atPath: settings.path) else { throw LegacyImportError.missingSettings }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacPilotLegacyUI-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let copied = directory.appendingPathComponent("settings.json")
        try FileManager.default.copyItem(at: settings, to: copied)
        return (directory, copied)
    }

    private func parseSettings(at url: URL) throws -> (settings: ImportedVoiceSettings, sttKey: String, llmKey: String) {
        guard let root = try? JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              let app = root["app_config"] as? [String: Any] else { throw LegacyImportError.corruptSettings }
        func string(_ key: String, _ fallback: String = "") -> String { app[key] as? String ?? fallback }
        let settings = ImportedVoiceSettings(
            sttProvider: string("stt_provider", "glm-asr"), sttLanguage: string("stt_language", "zh"),
            sttCustomBaseURL: string("stt_custom_base_url", "http://127.0.0.1:8000/v1"),
            sttCustomModel: string("stt_custom_model", "Systran/faster-whisper-large-v3"),
            llmProvider: string("llm_provider", "openrouter"), llmBaseURL: string("llm_base_url"), llmModel: string("llm_model"),
            hotkey: string("hotkey", "Option+/"), hotkeyMode: string("hotkey_mode", "hold"), polishEnabled: app["polish_enabled"] as? Bool ?? true
        )
        return (settings, string("stt_api_key"), string("llm_api_key"))
    }

    private func readDatabase(_ url: URL?) throws -> (history: [VoiceHistoryEntry], dictionary: [VoiceDictionaryEntry]) {
        guard let url else { return ([], []) }
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
            throw LegacyImportError.database("Unable to open copied database")
        }
        defer { sqlite3_close(database) }
        return (try readHistory(database), try readDictionary(database))
    }

    private func readHistory(_ db: OpaquePointer) throws -> [VoiceHistoryEntry] {
        var statement: OpaquePointer?
        let sql = "SELECT created_at, raw_text, polished_text, duration_ms FROM history ORDER BY id ASC"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw LegacyImportError.database("Invalid history schema") }
        defer { sqlite3_finalize(statement) }
        let formatter = ISO8601DateFormatter()
        var values: [VoiceHistoryEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let date = text(statement, 0).flatMap(formatter.date(from:)) ?? Date(timeIntervalSince1970: 0)
            values.append(.init(createdAt: date, rawText: text(statement, 1) ?? "", polishedText: text(statement, 2) ?? "", duration: Double(sqlite3_column_int64(statement, 3)) / 1_000))
        }
        return values
    }

    private func readDictionary(_ db: OpaquePointer) throws -> [VoiceDictionaryEntry] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id, word, pronunciation FROM dictionary ORDER BY id ASC", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LegacyImportError.database("Invalid dictionary schema")
        }
        defer { sqlite3_finalize(statement) }
        var values: [VoiceDictionaryEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            values.append(.init(id: sqlite3_column_int64(statement, 0), word: text(statement, 1) ?? "", pronunciation: text(statement, 2)))
        }
        return values
    }

    private func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }
}
