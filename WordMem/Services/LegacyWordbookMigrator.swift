import Foundation
import SwiftData

enum LegacyWordbookMigrator {
    static let migrationKey = "didMigrateLegacyWordbookToSwiftData"
    static let userSavedStatusUpgradeKey = "didUpgradeUserTranslationLookupStatus"
    private static let sourceKey = "saved_words"
    private static let backupKey = "saved_words.backup.beforeSwiftDataMigration"

    static func migrateIfNeeded(defaults: UserDefaults, into modelContext: ModelContext) throws {
        try upgradeUserTranslationStatus(defaults: defaults, in: modelContext)

        guard let sourceData = defaults.data(forKey: sourceKey) else {
            defaults.set(true, forKey: migrationKey)
            return
        }

        if !defaults.bool(forKey: migrationKey) {
            defaults.set(sourceData, forKey: backupKey)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacyWords = try decoder.decode([WordData].self, from: sourceData)
        let existingKeys = Set(
            try modelContext.fetch(FetchDescriptor<WordEntry>()).map(\.normalizedKey)
        )

        for legacyWord in legacyWords {
            let key = WordInputNormalizer.normalizedKey(from: legacyWord.word)
            guard !key.isEmpty, !existingKeys.contains(key) else { continue }

            let entry = WordEntry(
                originalInput: legacyWord.word,
                normalizedKey: key,
                headword: legacyWord.word,
                phonetic: legacyWord.phonetic,
                translation: legacyWord.translation,
                userTranslation: legacyWord.translation,
                legacyExample: legacyWord.example,
                legacyExampleSentence: legacyWord.exampleSentence,
                legacyTranslatedExampleSentence: legacyWord.translatedExampleSentence,
                lookupStatus: legacyWord.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .notFound : .userSaved,
                createdAt: legacyWord.createdAt,
                updatedAt: legacyWord.createdAt
            )
            modelContext.insert(entry)
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        defaults.set(true, forKey: migrationKey)
        defaults.removeObject(forKey: sourceKey)
    }

    /// Older releases labeled imported translations as `.notFound`, even when a
    /// machine/user translation was present. Distinguish that user data from a
    /// genuinely missing definition without losing dictionary enrichment.
    static func upgradeUserTranslationStatus(defaults: UserDefaults, in modelContext: ModelContext) throws {
        guard !defaults.bool(forKey: userSavedStatusUpgradeKey) else { return }

        let entries = try modelContext.fetch(FetchDescriptor<WordEntry>())
        var didChange = false
        for entry in entries where entry.lookupStatus == .notFound {
            let translation = entry.userTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translation.isEmpty else { continue }

            entry.lookupStatus = .userSaved
            entry.updatedAt = .now
            didChange = true
        }

        if didChange {
            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
                throw error
            }
        }

        defaults.set(true, forKey: userSavedStatusUpgradeKey)
    }
}
