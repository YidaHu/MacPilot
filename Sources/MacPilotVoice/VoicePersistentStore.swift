import CoreData
@preconcurrency import Foundation

public struct VoiceDictionaryEntry: Equatable, Sendable {
    public let id: Int64
    public let word: String
    public let pronunciation: String?
}

public struct VoiceScene: Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let prompt: String
}

public enum VoicePersistentStoreError: Error, Equatable {
    case historyNotFound
}

public final class VoicePersistentStore: @unchecked Sendable {
    private let container: NSPersistentContainer

    public init(inMemory: Bool = false, storeURL: URL? = nil) throws {
        container = NSPersistentContainer(name: "MacPilotVoice", managedObjectModel: Self.makeModel())
        let description = NSPersistentStoreDescription()
        if inMemory {
            description.type = NSInMemoryStoreType
            description.url = URL(fileURLWithPath: "/dev/null")
        } else {
            description.type = NSSQLiteStoreType
            let url = storeURL ?? Self.defaultStoreURL()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            description.url = url
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    public func history(limit: Int) throws -> [VoiceHistoryEntry] {
        try perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "HistoryEntry")
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            request.fetchLimit = max(limit, 0)
            return try container.viewContext.fetch(request).compactMap { object in
                guard let id = object.value(forKey: "id") as? UUID,
                      let createdAt = object.value(forKey: "createdAt") as? Date,
                      let raw = object.value(forKey: "rawText") as? String,
                      let polished = object.value(forKey: "polishedText") as? String else { return nil }
                return VoiceHistoryEntry(
                    id: id,
                    createdAt: createdAt,
                    rawText: raw,
                    polishedText: polished,
                    duration: object.value(forKey: "duration") as? Double ?? 0,
                    processingMode: VoiceProcessingMode(rawValue: object.value(forKey: "processingMode") as? String ?? "") ?? .standard,
                    processingStatus: VoiceProcessingStatus(rawValue: object.value(forKey: "processingStatus") as? String ?? "") ?? .success
                )
            }
        }
    }

    public func saveHistory(_ entry: VoiceHistoryEntry) throws {
        try perform {
            let object = NSEntityDescription.insertNewObject(forEntityName: "HistoryEntry", into: container.viewContext)
            object.setValue(entry.id, forKey: "id")
            object.setValue(entry.createdAt, forKey: "createdAt")
            object.setValue(entry.rawText, forKey: "rawText")
            object.setValue(entry.polishedText, forKey: "polishedText")
            object.setValue(entry.duration, forKey: "duration")
            object.setValue(entry.processingMode.rawValue, forKey: "processingMode")
            object.setValue(entry.processingStatus.rawValue, forKey: "processingStatus")
            try container.viewContext.save()
        }
    }

    public func updateHistory(id: UUID, polishedText: String) throws {
        try perform {
            guard let object = try historyObject(id: id) else { throw VoicePersistentStoreError.historyNotFound }
            object.setValue(polishedText, forKey: "polishedText")
            try container.viewContext.save()
        }
    }

    public func deleteHistory(id: UUID) throws {
        try perform {
            guard let object = try historyObject(id: id) else { throw VoicePersistentStoreError.historyNotFound }
            container.viewContext.delete(object)
            try container.viewContext.save()
        }
    }

    public func dictionary() throws -> [VoiceDictionaryEntry] {
        try perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "DictionaryEntry")
            request.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
            return try container.viewContext.fetch(request).compactMap { object in
                guard let word = object.value(forKey: "word") as? String else { return nil }
                return VoiceDictionaryEntry(id: object.value(forKey: "id") as? Int64 ?? 0, word: word, pronunciation: object.value(forKey: "pronunciation") as? String)
            }
        }
    }

    public func hasMigration(version: String) throws -> Bool {
        try perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "MigrationRecord")
            request.predicate = NSPredicate(format: "version == %@", version)
            request.fetchLimit = 1
            return try container.viewContext.count(for: request) > 0
        }
    }

    public func importLegacy(history: [VoiceHistoryEntry], dictionary: [VoiceDictionaryEntry], migrationVersion: String) throws {
        try perform {
            let context = container.viewContext
            do {
                for entry in history {
                    let object = NSEntityDescription.insertNewObject(forEntityName: "HistoryEntry", into: context)
                    object.setValue(entry.id, forKey: "id")
                    object.setValue(entry.createdAt, forKey: "createdAt")
                    object.setValue(entry.rawText, forKey: "rawText")
                    object.setValue(entry.polishedText, forKey: "polishedText")
                    object.setValue(entry.duration, forKey: "duration")
                    object.setValue(entry.processingMode.rawValue, forKey: "processingMode")
                    object.setValue(entry.processingStatus.rawValue, forKey: "processingStatus")
                }
                for entry in dictionary {
                    let object = NSEntityDescription.insertNewObject(forEntityName: "DictionaryEntry", into: context)
                    object.setValue(entry.id, forKey: "id")
                    object.setValue(entry.word, forKey: "word")
                    object.setValue(entry.pronunciation, forKey: "pronunciation")
                }
                let migration = NSEntityDescription.insertNewObject(forEntityName: "MigrationRecord", into: context)
                migration.setValue(migrationVersion, forKey: "version")
                migration.setValue(Date(), forKey: "createdAt")
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    private func perform<T>(_ body: () throws -> T) throws -> T {
        var result: Result<T, Error>!
        container.viewContext.performAndWait { result = Result { try body() } }
        return try result.get()
    }

    private func historyObject(id: UUID) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "HistoryEntry")
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        return try container.viewContext.fetch(request).first
    }

    private static func defaultStoreURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacPilot", isDirectory: true)
            .appendingPathComponent("Voice.sqlite")
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let history = entity("HistoryEntry", [
            attribute("id", .UUIDAttributeType, optional: false), attribute("createdAt", .dateAttributeType, optional: false),
            attribute("rawText", .stringAttributeType, optional: false), attribute("polishedText", .stringAttributeType, optional: false),
            attribute("duration", .doubleAttributeType, optional: false),
            attribute("processingMode", .stringAttributeType, optional: true),
            attribute("processingStatus", .stringAttributeType, optional: true)
        ])
        let dictionary = entity("DictionaryEntry", [
            attribute("id", .integer64AttributeType, optional: false), attribute("word", .stringAttributeType, optional: false),
            attribute("pronunciation", .stringAttributeType, optional: true)
        ])
        let scene = entity("Scene", [
            attribute("id", .UUIDAttributeType, optional: false), attribute("name", .stringAttributeType, optional: false),
            attribute("prompt", .stringAttributeType, optional: false)
        ])
        let migration = entity("MigrationRecord", [
            attribute("version", .stringAttributeType, optional: false), attribute("createdAt", .dateAttributeType, optional: false)
        ])
        model.entities = [history, dictionary, scene, migration]
        return model
    }

    private static func entity(_ name: String, _ properties: [NSPropertyDescription]) -> NSEntityDescription {
        let entity = NSEntityDescription(); entity.name = name; entity.managedObjectClassName = "NSManagedObject"; entity.properties = properties; return entity
    }

    private static func attribute(_ name: String, _ type: NSAttributeType, optional: Bool) -> NSAttributeDescription {
        let attribute = NSAttributeDescription(); attribute.name = name; attribute.attributeType = type; attribute.isOptional = optional; return attribute
    }
}

extension VoicePersistentStore: VoiceHistoryStoring {
    public func save(_ entry: VoiceHistoryEntry) async throws {
        try saveHistory(entry)
    }
}
