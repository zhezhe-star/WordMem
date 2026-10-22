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
        let candidates = rawWords.map {
            WordImportCandidatePayload(
                text: $0,
                normalizedKey: WordInputNormalizer.normalizedKey(from: $0)
            )
        }
        return try await importCandidates(
            candidates,
            source: source,
            sourceText: sourceText,
            imageData: imageData,
            recognizedText: recognizedText,
            submissionMetadata: [:],
            payloadID: nil,
            schemaVersion: nil,
            createdAt: nil,
            using: dictionaryService
        )
    }

    func importSubmission(
        _ submission: WordImportSubmission,
        using dictionaryService: any DictionaryLookupService
    ) async throws -> [AddWordOutcome] {
        guard !submission.candidates.isEmpty else {
            throw WordImportError.emptySelection
        }

        let candidates = submission.candidates.map { candidate in
            var normalized = candidate
            normalized.normalizedKey = WordInputNormalizer.normalizedKey(from: candidate.text)
                .replacingOccurrences(of: "'", with: "")
            return normalized
        }

        return try await importCandidates(
            candidates,
            source: submission.source,
            sourceText: submission.sourceText,
            imageData: nil,
            recognizedText: submission.recognizedText,
            submissionMetadata: submission.metadata,
            payloadID: submission.payloadID,
            schemaVersion: submission.schemaVersion,
            createdAt: submission.createdAt,
            using: dictionaryService
        )
    }

    private func importCandidates(
        _ structuredCandidates: [WordImportCandidatePayload],
        source: WordImportSource,
        sourceText: String?,
        imageData: Data?,
        recognizedText: String?,
        submissionMetadata: [String: String],
        payloadID: UUID?,
        schemaVersion: Int?,
        createdAt: Date?,
        using dictionaryService: any DictionaryLookupService
    ) async throws -> [AddWordOutcome] {
        var orderedInputs: [(input: WordImportCandidatePayload, initialKey: String)] = []
        var seenKeys = Set<String>()

        for candidate in structuredCandidates {
            let initialKey = WordInputNormalizer.normalizedKey(from: candidate.text)
                .replacingOccurrences(of: "'", with: "")
            guard !initialKey.isEmpty, seenKeys.insert(initialKey).inserted else { continue }
            orderedInputs.append((candidate, initialKey))
        }

        var lookups: [(input: WordImportCandidatePayload, result: DictionaryLookupResult)] = []

        for candidate in orderedInputs {
            let result = try await dictionaryService.lookup(candidate.input.text)
            lookups.append((candidate.input, result))
        }

        // Key by the caller's input so distinct words that resolve to one lemma keep distinct outcomes.
        var outcomeByInitialKey: [String: AddWordOutcome] = [:]

        do {
            for (index, lookup) in lookups.enumerated() {
                let initialKey = orderedInputs[index].initialKey
                let key = lookup.result.entry?.normalizedKey
                    ?? WordInputNormalizer.normalizedKey(from: lookup.input.text)

                if let existing = try findEntry(normalizedKey: key) {
                        if lookup.result.status != .notFound,
                           existing.lookupStatus == .notFound || existing.lookupStatus == .userSaved {
                            existing.apply(lookup.result)
                        }
                        applySuppliedFields(lookup.input, to: existing)

                    insertImportContext(
                        for: existing,
                        input: lookup.input,
                        source: source,
                        sourceText: sourceText,
                        imageData: imageData,
                        recognizedText: recognizedText,
                        submissionMetadata: submissionMetadata,
                        payloadID: payloadID,
                        schemaVersion: schemaVersion,
                        createdAt: createdAt
                    )
                    outcomeByInitialKey[initialKey] = .duplicate(existing)
                } else {
                    let entry = WordEntry(
                        originalInput: lookup.input.text,
                        normalizedKey: key,
                        headword: key
                    )
                    modelContext.insert(entry)
                    // See add(_:using:) for the iOS 27 SwiftData registration workaround.
                    entry.apply(lookup.result)
                    applySuppliedFields(lookup.input, to: entry)
                    insertImportContext(
                        for: entry,
                        input: lookup.input,
                        source: source,
                        sourceText: sourceText,
                        imageData: imageData,
                        recognizedText: recognizedText,
                        submissionMetadata: submissionMetadata,
                        payloadID: payloadID,
                        schemaVersion: schemaVersion,
                        createdAt: createdAt
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
        input: WordImportCandidatePayload,
        source: WordImportSource,
        sourceText: String?,
        imageData: Data?,
        recognizedText: String?,
        submissionMetadata: [String: String],
        payloadID: UUID?,
        schemaVersion: Int?,
        createdAt: Date?
    ) {
        var metadata: [String: String] = [:]
        metadata["candidateLength"] = "\(input.text.count)"
        submissionMetadata.forEach { metadata[$0.key] = $0.value }
        input.metadata.forEach { metadata[$0.key] = $0.value }
        if let payloadID {
            metadata["payloadID"] = payloadID.uuidString
        }
        if let schemaVersion {
            metadata["payloadSchemaVersion"] = "\(schemaVersion)"
        }
        if let createdAt {
            metadata["submissionCreatedAt"] = ISO8601DateFormatter().string(from: createdAt)
        }
        if let note = input.userNote, !note.isEmpty {
            metadata["userNote"] = note
        }
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
                    selectedCandidate: input.text,
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

    private func applySuppliedFields(_ candidate: WordImportCandidatePayload, to entry: WordEntry) {
        let translation = candidate.userTranslation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let phonetic = candidate.userPhonetic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let example = candidate.userExample?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !translation.isEmpty {
            entry.userTranslation = translation
        }
        if !phonetic.isEmpty {
            entry.phonetic = phonetic
        }
        if !example.isEmpty {
            entry.legacyExample = example
        }
    }
}

@MainActor
enum WordImportSubmissionMigrator {
    static func processPendingSubmissions(
        defaults: UserDefaults,
        into modelContext: ModelContext,
        dictionaryService: any DictionaryLookupService
    ) async throws {
        let submissions = WordImportSubmissionQueue.load(from: defaults)
            .sorted {
                if $0.createdAt != $1.createdAt {
                    $0.createdAt < $1.createdAt
                } else {
                    $0.payloadID.uuidString < $1.payloadID.uuidString
                }
            }

        var processedIDs = Set<UUID>()
        do {
            for submission in submissions {
                _ = try await WordbookRepository(modelContext: modelContext).importSubmission(
                    submission,
                    using: dictionaryService
                )
                processedIDs.insert(submission.payloadID)
            }
        } catch {
            WordImportSubmissionQueue.remove(processedIDs, from: defaults)
            throw error
        }

        WordImportSubmissionQueue.remove(processedIDs, from: defaults)
    }
}

enum WordImportError: Error, Equatable {
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
