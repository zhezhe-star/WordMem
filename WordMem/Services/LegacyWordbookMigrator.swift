import Foundation
import SwiftData

@MainActor
enum LegacyWordbookMigrator {
    static let migrationKey = "didMigrateLegacyWordbookToSwiftData"
    static let userSavedStatusUpgradeKey = "didUpgradeUserTranslationLookupStatus"
    static let localDictionaryEnrichmentKey = "didEnrichUserSavedEntriesWithLocalDictionary"
    private static let sourceKey = "saved_words"
    private static let backupKey = "saved_words.backup.beforeSwiftDataMigration"

    static func migrateIfNeeded(
        defaults: UserDefaults,
        into modelContext: ModelContext,
        dictionaryService: (any DictionaryLookupService)? = nil
    ) async throws {
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
        var existingKeys = Set(
            try modelContext.fetch(FetchDescriptor<WordEntry>()).map(\.normalizedKey)
        )

        for legacyWord in legacyWords {
            let key = WordInputNormalizer.normalizedKey(from: legacyWord.word)
            guard !key.isEmpty, !existingKeys.contains(key) else { continue }

            let lookupResult = try await dictionaryService?.lookup(legacyWord.word)
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
            try applyDictionaryResult(lookupResult, to: entry, in: modelContext)
            modelContext.insert(entry)
            existingKeys.insert(key)
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        defaults.set(true, forKey: migrationKey)
        defaults.removeObject(forKey: sourceKey)

        if let dictionaryService {
            try await enrichUserSavedEntries(
                defaults: defaults,
                in: modelContext,
                dictionaryService: dictionaryService
            )
        }
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

    /// One-time backfill for entries imported by builds that did not consult the
    /// bundled dictionary while consuming the extension queue.
    static func enrichUserSavedEntries(
        defaults: UserDefaults,
        in modelContext: ModelContext,
        dictionaryService: any DictionaryLookupService
    ) async throws {
        guard !defaults.bool(forKey: localDictionaryEnrichmentKey) else { return }

        let entries = try modelContext.fetch(FetchDescriptor<WordEntry>())
        var didChange = false

        for entry in entries where entry.lookupStatus == .userSaved {
            let result = try await dictionaryService.lookup(entry.originalInput)
            guard try applyDictionaryResult(result, to: entry, in: modelContext) else { continue }
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

        defaults.set(true, forKey: localDictionaryEnrichmentKey)
    }

    @discardableResult
    private static func applyDictionaryResult(
        _ result: DictionaryLookupResult?,
        to entry: WordEntry,
        in modelContext: ModelContext
    ) throws -> Bool {
        guard let result,
              result.status != .notFound,
              result.entry != nil,
              entry.lookupStatus == .notFound || entry.lookupStatus == .userSaved
        else { return false }

        let canonicalKey = result.entry?.normalizedKey ?? entry.normalizedKey
        if canonicalKey != entry.normalizedKey {
            var descriptor = FetchDescriptor<WordEntry>(
                predicate: #Predicate { $0.normalizedKey == canonicalKey }
            )
            descriptor.fetchLimit = 1
            descriptor.includePendingChanges = true
            if let duplicate = try modelContext.fetch(descriptor).first,
               duplicate.id != entry.id {
                return false
            }
        }

        entry.apply(result)
        entry.normalizedKey = canonicalKey
        return true
    }
}
