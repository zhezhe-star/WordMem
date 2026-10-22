import Foundation
import SwiftData

@MainActor
enum AddWordOutcome {
    case added(WordEntry)
    case duplicate(WordEntry)

    var entry: WordEntry {
        switch self {
        case .added(let entry), .duplicate(let entry):
            entry
        }
    }
}

@MainActor
struct WordbookRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func add(_ rawInput: String, using dictionaryService: any DictionaryLookupService) async throws -> AddWordOutcome {
        let result = try await dictionaryService.lookup(rawInput)
        let key = result.entry?.normalizedKey ?? WordInputNormalizer.normalizedKey(from: rawInput)

        if let existing = try findEntry(normalizedKey: key) {
            if result.status != .notFound, existing.lookupStatus == .notFound || existing.lookupStatus == .userSaved {
                existing.apply(result)
                do {
                    try modelContext.save()
                } catch {
                    modelContext.rollback()
                    throw error
                }
            }

            return .duplicate(existing)
        }

        let entry = WordEntry(originalInput: rawInput, normalizedKey: key, headword: key)
        entry.apply(result)
        modelContext.insert(entry)

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        return .added(entry)
    }

    func undoAdd(_ entry: WordEntry) throws {
        modelContext.delete(entry)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func findEntry(normalizedKey key: String) throws -> WordEntry? {
        var descriptor = FetchDescriptor<WordEntry>(
            predicate: #Predicate { $0.normalizedKey == key }
        )
        descriptor.fetchLimit = 1
        descriptor.includePendingChanges = true
        return try modelContext.fetch(descriptor).first
    }
}
