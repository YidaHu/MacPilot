import SQLite3
import XCTest
@testable import MacPilotVoice

final class LegacyImporterTests: XCTestCase {
    func testSettingsV2ImportsStructuredFieldsAfterV1WithoutDuplicatingHistory() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let store = try VoicePersistentStore(inMemory: true)
        let keychain = KeychainStore(service: "com.huyida.macpilot.voice.v2-tests.\(UUID().uuidString)")
        defer { try? keychain.delete(account: "stt.glm-asr"); try? keychain.delete(account: "llm.zhipu") }
        let importer = LegacyOpenTypelessImporter(store: store, keychain: keychain)
        _ = try importer.importData(from: fixture.directory)

        let settings = try importer.importVoiceUISettings(from: fixture.directory)

        XCTAssertTrue(settings.structuredDictationEnabled)
        XCTAssertEqual(settings.structuredDictationPrompt, "按主题忠实整理")
        XCTAssertFalse(settings.alreadyImported)
        XCTAssertEqual(try store.history(limit: 10).count, 1)
        XCTAssertTrue(try store.hasMigration(version: LegacyOpenTypelessImporter.voiceUIMigrationVersion))

        let second = try importer.importVoiceUISettings(from: fixture.directory)
        XCTAssertTrue(second.alreadyImported)
        XCTAssertTrue(second.structuredDictationEnabled)
        XCTAssertEqual(second.structuredDictationPrompt, "按主题忠实整理")
        XCTAssertEqual(try store.history(limit: 10).count, 1)
    }

    func testImportsSettingsHistoryDictionaryAndSecretsWithoutMutatingSource() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let originalSettings = try Data(contentsOf: fixture.directory.appendingPathComponent("settings.json"))
        let store = try VoicePersistentStore(inMemory: true)
        let keychain = KeychainStore(service: "com.huyida.macpilot.voice.import-tests.\(UUID().uuidString)")
        defer { try? keychain.delete(account: "stt.glm-asr"); try? keychain.delete(account: "llm.zhipu") }
        let importer = LegacyOpenTypelessImporter(store: store, keychain: keychain)

        let summary = try importer.importData(from: fixture.directory)

        XCTAssertEqual(summary.historyCount, 1)
        XCTAssertEqual(summary.dictionaryCount, 1)
        XCTAssertEqual(summary.settings.sttProvider, "glm-asr")
        XCTAssertEqual(summary.settings.sttCustomBaseURL, "http://127.0.0.1:8000/v1")
        XCTAssertEqual(summary.settings.sttCustomModel, "local-whisper")
        XCTAssertEqual(try store.history(limit: 10).first?.polishedText, "整理后的文本")
        XCTAssertEqual(try store.dictionary().first?.word, "MacPilot")
        XCTAssertEqual(try keychain.string(account: "stt.glm-asr"), "dummy-stt-key")
        XCTAssertEqual(try Data(contentsOf: fixture.directory.appendingPathComponent("settings.json")), originalSettings)

        let second = try importer.importData(from: fixture.directory)
        XCTAssertTrue(second.alreadyImported)
        XCTAssertEqual(try store.history(limit: 10).count, 1)
    }

    func testCorruptSettingsRollsBackImport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: directory.appendingPathComponent("settings.json"))
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try VoicePersistentStore(inMemory: true)
        let importer = LegacyOpenTypelessImporter(store: store, keychain: KeychainStore(service: "com.huyida.macpilot.voice.import-tests.\(UUID().uuidString)"))

        XCTAssertThrowsError(try importer.importData(from: directory))
        XCTAssertTrue(try store.history(limit: 10).isEmpty)
        XCTAssertFalse(try store.hasMigration(version: LegacyOpenTypelessImporter.migrationVersion))
    }

    private func makeFixture() throws -> (directory: URL, database: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settings: [String: Any] = ["app_config": [
            "stt_provider": "glm-asr", "stt_api_key": "dummy-stt-key", "stt_language": "zh",
            "stt_custom_base_url": "http://127.0.0.1:8000/v1", "stt_custom_model": "local-whisper",
            "llm_provider": "zhipu", "llm_api_key": "dummy-llm-key", "llm_base_url": "https://example.test/v1",
            "llm_model": "glm-test", "hotkey": "Option+/", "hotkey_mode": "toggle", "polish_enabled": true,
            "structured_dictation_enabled": true, "polish_custom_prompt": "按主题忠实整理"
        ]]
        try JSONSerialization.data(withJSONObject: settings).write(to: directory.appendingPathComponent("settings.json"))

        let database = directory.appendingPathComponent("opentypeless.db")
        var db: OpaquePointer?
        guard sqlite3_open(database.path, &db) == SQLITE_OK, let db else { throw NSError(domain: "test.sqlite", code: 1) }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "CREATE TABLE history (id INTEGER PRIMARY KEY, created_at TEXT, app_name TEXT, app_type TEXT, raw_text TEXT, polished_text TEXT, language TEXT, duration_ms INTEGER);", nil, nil, nil)
        sqlite3_exec(db, "INSERT INTO history VALUES (1, '2026-07-12T10:00:00Z', 'Notes', 'document', '原始文本', '整理后的文本', 'zh', 1200);", nil, nil, nil)
        sqlite3_exec(db, "CREATE TABLE dictionary (id INTEGER PRIMARY KEY, word TEXT, pronunciation TEXT);", nil, nil, nil)
        sqlite3_exec(db, "INSERT INTO dictionary VALUES (1, 'MacPilot', NULL);", nil, nil, nil)
        return (directory, database)
    }
}
