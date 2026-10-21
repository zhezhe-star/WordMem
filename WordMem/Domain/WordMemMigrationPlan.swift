import Foundation
import SwiftData

/// Semantic snapshot transferred between the two migration callbacks.
private struct LegacyA0ImportRow: Codable {
    var entryID: UUID
    var id: UUID
    var sourceRawValue: String
    var sourceText: String?
    var selectedCandidate: String?
    var recognizedText: String?
    var imageData: Data?
    var metadata: [String: String]
    var createdAt: Date
}

private struct LegacyA0ImportPayload: Codable {
    var rows: [LegacyA0ImportRow]
}

private struct LegacyA0EntryRow: Codable {
    var id: UUID
    var originalInput: String
    var normalizedKey: String
    var headword: String
    var phonetic: String?
    var translation: String
    var userTranslation: String
    var legacyExample: String?
    var legacyExampleSentence: String?
    var legacyTranslatedExampleSentence: String?
    var sensesData: Data
    var formsData: Data
    var tagsData: Data
    var lookupStatusRawValue: String
    var dictionaryID: String?
    var dictionaryVersion: String?
    var createdAt: Date
    var updatedAt: Date
}

private struct LegacyA0MigrationPayload: Codable {
    var entries: [LegacyA0EntryRow]
    var contexts: [LegacyA0ImportRow]
}

@Model
final class LegacyA0WordEntry {
    var id: UUID
    var originalInput: String
    @Attribute(.unique) var normalizedKey: String
    var headword: String
    var phonetic: String?
    var translation: String
    var userTranslation: String
    var legacyExample: String?
    var legacyExampleSentence: String?
    var legacyTranslatedExampleSentence: String?
    // Internal so the same-file migration payload can move the encoded values.
    var sensesData: Data
    var formsData: Data
    var tagsData: Data
    var lookupStatusRawValue: String
    var dictionaryID: String?
    var dictionaryVersion: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        originalInput: String,
        normalizedKey: String,
        headword: String,
        phonetic: String?,
        translation: String,
        userTranslation: String,
        legacyExample: String?,
        legacyExampleSentence: String?,
        legacyTranslatedExampleSentence: String?,
        senses: [WordSense],
        forms: [WordForm],
        tags: [String],
        lookupStatus: LookupStatus,
        dictionaryID: String?,
        dictionaryVersion: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.originalInput = originalInput
        self.normalizedKey = normalizedKey
        self.headword = headword
        self.phonetic = phonetic
        self.translation = translation
        self.userTranslation = userTranslation
        self.legacyExample = legacyExample
        self.legacyExampleSentence = legacyExampleSentence
        self.legacyTranslatedExampleSentence = legacyTranslatedExampleSentence
        self.sensesData = (try? JSONEncoder().encode(senses)) ?? Data()
        self.formsData = (try? JSONEncoder().encode(forms)) ?? Data()
        self.tagsData = (try? JSONEncoder().encode(tags)) ?? Data()
        self.lookupStatusRawValue = lookupStatus.rawValue
        self.dictionaryID = dictionaryID
        self.dictionaryVersion = dictionaryVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Represents the a0 import-context schema for compatibility tests and migrations.
///
/// SwiftData identifies a model entity by its `@Model` type and `VersionedSchema`
/// does not provide an entity-renaming API. The real a0 store therefore used the
/// entity names `WordEntry` and `WordImportContext`; the compatibility types must
/// instead be named `LegacyA0*` to coexist with the current same-named models.
/// This is the explicit, documented boundary: the plan verifies semantic a0
/// preservation with an explicit migration, but cannot literally reuse those old
/// entity names in-process.
@Model
final class LegacyA0WordImportContext {
    var id: UUID
    var sourceRawValue: String
    var sourceText: String?
    var selectedCandidate: String?
    var recognizedText: String?
    var imageData: Data?
    private var metadataData: Data
    var createdAt: Date
    @Relationship var entry: LegacyA0WordEntry?

    var metadata: [String: String] {
        get {
            guard !metadataData.isEmpty else { return [:] }
            return (try? JSONDecoder().decode([String: String].self, from: metadataData)) ?? [:]
        }
        set {
            metadataData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    init(
        id: UUID,
        entry: LegacyA0WordEntry?,
        sourceRawValue: String,
        sourceText: String?,
        selectedCandidate: String?,
        recognizedText: String?,
        imageData: Data?,
        metadata: [String: String],
        createdAt: Date
    ) {
        self.id = id
        self.entry = entry
        self.sourceRawValue = sourceRawValue
        self.sourceText = sourceText
        self.selectedCandidate = selectedCandidate
        self.recognizedText = recognizedText
        self.imageData = imageData
        self.metadataData = (try? JSONEncoder().encode(metadata)) ?? Data()
        self.createdAt = createdAt
    }
}

enum WordMemSchemaA0: VersionedSchema {
    static let models: [any PersistentModel.Type] = [
        LegacyA0WordEntry.self,
        LegacyA0WordImportContext.self,
    ]

    static let versionIdentifier = Schema.Version(1, 0, 0)
}

enum WordMemSchemaCurrent: VersionedSchema {
    static let models: [any PersistentModel.Type] = [
        WordEntry.self,
        WordImportContext.self,
    ]

    static let versionIdentifier = Schema.Version(2, 0, 0)
}

enum WordMemMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [
        WordMemSchemaA0.self,
        WordMemSchemaCurrent.self,
    ]

    static var legacyImportPayloadURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("WordMemA0ImportMigration.json")
    }

    static let stages: [MigrationStage] = [
        .custom(
            fromVersion: WordMemSchemaA0.self,
            toVersion: WordMemSchemaCurrent.self,
            willMigrate: { context in
                let legacyEntries = try context.fetch(FetchDescriptor<LegacyA0WordEntry>())
                let legacyContexts = try context.fetch(FetchDescriptor<LegacyA0WordImportContext>())
                let entries = legacyEntries.map { legacy in
                    LegacyA0EntryRow(
                        id: legacy.id,
                        originalInput: legacy.originalInput,
                        normalizedKey: legacy.normalizedKey,
                        headword: legacy.headword,
                        phonetic: legacy.phonetic,
                        translation: legacy.translation,
                        userTranslation: legacy.userTranslation,
                        legacyExample: legacy.legacyExample,
                        legacyExampleSentence: legacy.legacyExampleSentence,
                        legacyTranslatedExampleSentence: legacy.legacyTranslatedExampleSentence,
                        sensesData: legacy.sensesData,
                        formsData: legacy.formsData,
                        tagsData: legacy.tagsData,
                        lookupStatusRawValue: legacy.lookupStatusRawValue,
                        dictionaryID: legacy.dictionaryID,
                        dictionaryVersion: legacy.dictionaryVersion,
                        createdAt: legacy.createdAt,
                        updatedAt: legacy.updatedAt
                    )
                }
                let contexts = legacyContexts.map { legacy in
                    LegacyA0ImportRow(
                        entryID: legacy.entry?.id ?? UUID(),
                        id: legacy.id,
                        sourceRawValue: legacy.sourceRawValue,
                        sourceText: legacy.sourceText,
                        selectedCandidate: legacy.selectedCandidate,
                        recognizedText: legacy.recognizedText,
                        imageData: legacy.imageData,
                        metadata: legacy.metadata,
                        createdAt: legacy.createdAt
                    )
                }
                let payload = LegacyA0MigrationPayload(entries: entries, contexts: contexts)
                let data = try JSONEncoder().encode(payload)
                try data.write(to: legacyImportPayloadURL, options: .atomic)
            },
            didMigrate: { context in
                let data = try Data(contentsOf: legacyImportPayloadURL)
                let payload = try JSONDecoder().decode(LegacyA0MigrationPayload.self, from: data)
                var entriesByID: [UUID: WordEntry] = [:]

                for row in payload.entries {
                    let entry = WordEntry(
                        id: row.id,
                        originalInput: row.originalInput,
                        normalizedKey: row.normalizedKey,
                        headword: row.headword,
                        phonetic: row.phonetic,
                        translation: row.translation,
                        userTranslation: row.userTranslation,
                        legacyExample: row.legacyExample,
                        legacyExampleSentence: row.legacyExampleSentence,
                        legacyTranslatedExampleSentence: row.legacyTranslatedExampleSentence,
                        lookupStatus: LookupStatus(rawValue: row.lookupStatusRawValue) ?? .notFound,
                        dictionaryID: row.dictionaryID,
                        dictionaryVersion: row.dictionaryVersion,
                        createdAt: row.createdAt,
                        updatedAt: row.updatedAt
                    )
                    entry.senses = (try? JSONDecoder().decode([WordSense].self, from: row.sensesData)) ?? []
                    entry.forms = (try? JSONDecoder().decode([WordForm].self, from: row.formsData)) ?? []
                    entry.tags = (try? JSONDecoder().decode([String].self, from: row.tagsData)) ?? []
                    context.insert(entry)
                    entriesByID[row.id] = entry
                }

                for row in payload.contexts {
                    context.insert(
                        WordImportContext(
                            id: row.id,
                            entry: entriesByID[row.entryID],
                            source: WordImportSource(rawValue: row.sourceRawValue) ?? .manual,
                            sourceText: row.sourceText,
                            selectedCandidate: row.selectedCandidate,
                            recognizedText: row.recognizedText,
                            imageData: row.imageData,
                            metadata: row.metadata,
                            createdAt: row.createdAt
                        )
                    )
                }

                try context.save()
                try? FileManager.default.removeItem(at: legacyImportPayloadURL)
            }
        )
    ]
}
