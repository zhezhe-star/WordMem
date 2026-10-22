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
    private let saveAction: @MainActor (ModelContext) throws -> Void

    init(
        modelContext: ModelContext,
        save saveAction: (@MainActor (ModelContext) throws -> Void)? = nil
    ) {
        self.modelContext = modelContext
        self.saveAction = saveAction ?? { context in
            try context.save()
        }
    }

    func add(_ rawInput: String, using dictionaryService: any DictionaryLookupService) async throws -> AddWordOutcome {
        let result = try await dictionaryService.lookup(rawInput)
        let key = result.entry?.normalizedKey ?? WordInputNormalizer.normalizedKey(from: rawInput)

        if let existing = try findEntry(normalizedKey: key) {
            if result.status != .notFound, existing.lookupStatus == .notFound || existing.lookupStatus == .userSaved {
                existing.apply(result)
            }

            let context = WordImportContext(
                entry: existing,
                source: .manual,
                selectedCandidate: rawInput
            )
            modelContext.insert(context)

            do {
                try saveAction(modelContext)
            } catch {
                modelContext.rollback()
                throw error
            }

            return .duplicate(existing)
        }

        let entry = WordEntry(originalInput: rawInput, normalizedKey: key, headword: key)
        let context = WordImportContext(
            entry: entry,
            source: .manual,
            selectedCandidate: rawInput
        )
        modelContext.insert(entry)
        // iOS 27 SwiftData can reset values assigned before insert, so enrich after registration.
        entry.apply(result)
        modelContext.insert(context)

        do {
            try saveAction(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }

        return .added(entry)
    }

    func importWords(
        _ rawWords: [String],
        source: WordImportSource,
        sourceText: String? = nil,
        imageData: Data? = nil,
        recognizedText: String? = nil,
        using dictionaryService: any DictionaryLookupService
    ) async throws -> [AddWordOutcome] {
        var orderedInputs: [(input: String, initialKey: String)] = []
        var seenKeys = Set<String>()

        for rawWord in rawWords {
            let initialKey = WordInputNormalizer.normalizedKey(from: rawWord)
                .replacingOccurrences(of: "'", with: "")
            guard !initialKey.isEmpty, seenKeys.insert(initialKey).inserted else { continue }
            orderedInputs.append((rawWord, initialKey))
        }

        var lookups: [(input: String, result: DictionaryLookupResult)] = []

        for candidate in orderedInputs {
            let result = try await dictionaryService.lookup(candidate.input)
            lookups.append((candidate.input, result))
        }

        // Key by the caller's input so distinct words that resolve to one lemma keep distinct outcomes.
        var outcomeByInitialKey: [String: AddWordOutcome] = [:]

        do {
            for (index, lookup) in lookups.enumerated() {
                let initialKey = orderedInputs[index].initialKey
                let key = lookup.result.entry?.normalizedKey
                    ?? WordInputNormalizer.normalizedKey(from: lookup.input)

                if let existing = try findEntry(normalizedKey: key) {
                    if lookup.result.status != .notFound, existing.lookupStatus == .notFound {
                        existing.apply(lookup.result)
                    }

                    insertImportContext(
                        for: existing,
                        input: lookup.input,
                        source: source,
                        sourceText: sourceText,
                        imageData: imageData,
                        recognizedText: recognizedText
                    )
                    outcomeByInitialKey[initialKey] = .duplicate(existing)
                } else {
                    let entry = WordEntry(
                        originalInput: lookup.input,
                        normalizedKey: key,
                        headword: key
                    )
                    modelContext.insert(entry)
                    // See add(_:using:) for the iOS 27 SwiftData registration workaround.
                    entry.apply(lookup.result)
                    insertImportContext(
                        for: entry,
                        input: lookup.input,
                        source: source,
                        sourceText: sourceText,
                        imageData: imageData,
                        recognizedText: recognizedText
                    )
                    outcomeByInitialKey[initialKey] = .added(entry)
                }
            }

            try saveAction(modelContext)
            return orderedInputs.compactMap { candidate in
                outcomeByInitialKey[candidate.initialKey]
            }
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func addDefaultAppImport(
        _ rawInput: String,
        originalText: String,
        using dictionaryService: any DictionaryLookupService
    ) async throws -> AddWordOutcome {
        let outcomes = try await importWords(
            [rawInput],
            source: .defaultApp,
            sourceText: originalText,
            using: dictionaryService
        )

        guard let outcome = outcomes.first else {
            throw WordImportError.emptySelection
        }

        return outcome
    }

    func undoAdd(_ entry: WordEntry) throws {
        try deleteImportContexts(for: [entry])
        modelContext.delete(entry)
        do {
            try saveAction(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func deleteWords(_ entries: [WordEntry]) throws {
        try deleteImportContexts(for: entries)
        entries.forEach(modelContext.delete)
        do {
            try saveAction(modelContext)
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

    private func insertImportContext(
        for entry: WordEntry,
        input: String,
        source: WordImportSource,
        sourceText: String?,
        imageData: Data?,
        recognizedText: String?
    ) {
        var metadata: [String: String] = [:]
        metadata["candidateLength"] = "\(input.count)"
        if let sourceText {
            metadata["sourceTextLength"] = "\(sourceText.count)"
        }
        if let recognizedText {
            metadata["recognizedTextLength"] = "\(recognizedText.count)"
        }
        if let imageData, !imageData.isEmpty {
            metadata["imageByteCount"] = "\(imageData.count)"
        }

        modelContext.insert(
            WordImportContext(
                entry: entry,
                source: source,
                sourceText: sourceText,
                selectedCandidate: input,
                recognizedText: recognizedText,
                imageData: imageData,
                metadata: metadata
            )
        )
    }

    private func deleteImportContexts(for entries: [WordEntry]) throws {
        for entry in entries {
            let entryID = entry.id
            try modelContext.delete(
                model: WordImportContext.self,
                where: #Predicate<WordImportContext> { context in
                    context.entryID == entryID
                }
            )
        }
    }
}

enum WordImportError: Error {
    case emptySelection
}

@MainActor
enum WordImportContextMigrator {
    static let backfillCompletedKey = "wordImportContextEntryIDBackfill.v1.completed"

    static func backfillEntryIDs(
        in modelContext: ModelContext,
        defaults: UserDefaults = .standard,
        save saveAction: ((ModelContext) throws -> Void)? = nil
    ) throws {
        guard !defaults.bool(forKey: backfillCompletedKey) else { return }

        let migrationContext = ModelContext(modelContext.container)
        var descriptor = FetchDescriptor<WordImportContext>(
            predicate: #Predicate<WordImportContext> { context in
                context.entryID == nil
            }
        )
        descriptor.propertiesToFetch = [\.entryID, \.entry]
        let legacyContexts = try migrationContext.fetch(descriptor)

        for context in legacyContexts {
            context.entryID = context.entry?.id
        }

        guard legacyContexts.contains(where: { $0.entryID != nil }) else {
            defaults.set(true, forKey: backfillCompletedKey)
            return
        }

        let performSave = saveAction ?? { context in
            try context.save()
        }
        do {
            try performSave(migrationContext)
        } catch {
            migrationContext.rollback()
            throw error
        }
        defaults.set(true, forKey: backfillCompletedKey)
    }
}
