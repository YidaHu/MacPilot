import Foundation

public struct ReminderRecord: Codable, Equatable, Hashable {
    public let key: ReminderKey
    public let remindedAt: Date
}

public final class ReminderStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func loadRecords() throws -> Set<ReminderRecord> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return Set(try decoder.decode([ReminderRecord].self, from: data))
    }

    public func remindedKeys() throws -> Set<ReminderKey> { Set(try loadRecords().map(\.key)) }
    public func hasReminded(event: CalendarEventSnapshot) throws -> Bool { try remindedKeys().contains(event.reminderKey) }

    public func markReminded(event: CalendarEventSnapshot, remindedAt: Date) throws {
        var records = try loadRecords().filter { $0.key != event.reminderKey }
        records.insert(ReminderRecord(key: event.reminderKey, remindedAt: remindedAt))
        try save(records)
    }

    public func pruneRecords(before cutoff: Date) throws {
        try save(try loadRecords().filter { $0.key.startDate >= cutoff })
    }

    private func save(_ records: Set<ReminderRecord>) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sorted = records.sorted { $0.key.startDate == $1.key.startDate ? $0.key.eventID < $1.key.eventID : $0.key.startDate < $1.key.startDate }
        try encoder.encode(sorted).write(to: fileURL, options: .atomic)
    }
}
