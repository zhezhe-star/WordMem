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
            if result.status != .notFound, existing.lookupStatus == .notFound {
                existing.apply(result)
            }

            let context = WordImportContext(
                entry: existing,
                source: .manual,
                selectedCandidate: rawInput
            )
            modelContext.insert(context)

            do {
                try modelContext.save()
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
        entry.apply(result)
        modelContext.insert(context)

        do {
            try modelContext.save()
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
        var resolvedKeyByInitialKey: [String: String] = [:]
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
            let key = result.entry?.normalizedKey ?? WordInputNormalizer.normalizedKey(from: candidate.input)
            resolvedKeyByInitialKey[candidate.initialKey] = key
            lookups.append((candidate.input, result))
        }

        var outcomeByKey: [String: AddWordOutcome] = [:]

        do {
            for lookup in lookups {
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
                    outcomeByKey[key] = .duplicate(existing)
                } else {
                    let entry = WordEntry(
                        originalInput: lookup.input,
                        normalizedKey: key,
                        headword: key
                    )
                    modelContext.insert(entry)
                    entry.apply(lookup.result)
                    insertImportContext(
                        for: entry,
                        input: lookup.input,
                        source: source,
                        sourceText: sourceText,
                        imageData: imageData,
                        recognizedText: recognizedText
                    )
                    outcomeByKey[key] = .added(entry)
                }
            }

            try modelContext.save()
            return orderedInputs.compactMap { candidate in
                guard let key = resolvedKeyByInitialKey[candidate.initialKey] else { return nil }
                return outcomeByKey[key]
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
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func deleteWords(_ entries: [WordEntry]) throws {
        try deleteImportContexts(for: entries)
        entries.forEach(modelContext.delete)
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
        let entryIDs = entries.map(\.id)
        try modelContext.fetch(FetchDescriptor<WordImportContext>())
            .filter { context in
                guard let id = context.entry?.id else { return false }
                return entryIDs.contains(id)
            }
            .forEach(modelContext.delete)
    }
}

enum WordImportError: Error {
    case emptySelection
}
