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
        self.saveAction =
            saveAction ?? { context in
                try context.save()
            }
    }

    @available(*, deprecated, message: "Use importSubmission(_:using:).")
    func add(_ rawInput: String, using dictionaryService: any DictionaryLookupService) async throws
        -> AddWordOutcome
    {
        let submission = WordImportSubmission(
            source: .manual,
            sourceText: rawInput,
            candidates: [
                WordImportCandidatePayload(
                    text: rawInput,
                    normalizedKey: WordInputNormalizer.normalizedKey(from: rawInput)
                )
            ],
            metadata: ["channel": WordImportSource.manual.rawValue]
        )
        let outcomes = try await importSubmission(submission, using: dictionaryService)
        guard let outcome = outcomes.first else { throw WordImportError.emptySelection }
        return outcome
    }

    @available(*, deprecated, message: "Use importSubmission(_:using:).")
    func importWords(
        _ rawWords: [String],
        source: WordImportSource,
        sourceText: String? = nil,
        imageData: Data? = nil,
        recognizedText: String? = nil,
        using dictionaryService: any DictionaryLookupService
    ) async throws -> [AddWordOutcome] {
        let submission = WordImportSubmission(
            source: source,
            sourceText: sourceText ?? "",
            recognizedText: recognizedText,
            imageData: imageData,
            candidates: rawWords.map {
                WordImportCandidatePayload(
                    text: $0,
                    normalizedKey: WordInputNormalizer.normalizedKey(from: $0)
                )
            }
        )
        return try await importSubmission(submission, using: dictionaryService)
    }

    func importSubmission(
        _ submission: WordImportSubmission,
        using dictionaryService: any DictionaryLookupService
    ) async throws -> [AddWordOutcome] {
        let candidates = normalizedSubmissionCandidates(in: submission)
        guard !candidates.isEmpty else { throw WordImportError.emptySelection }

        return try await importCandidates(
            candidates,
            source: submission.source,
            sourceText: submission.sourceText,
            imageData: submission.imageData,
            recognizedText: submission.recognizedText,
            submissionMetadata: submission.metadata,
            payloadID: submission.payloadID,
            schemaVersion: submission.schemaVersion,
            createdAt: submission.createdAt,
            using: dictionaryService
        )
    }

    func hasCompletedImport(_ submission: WordImportSubmission) throws -> Bool {
        let expectedIDs = Set(normalizedSubmissionCandidates(in: submission).map(\.payloadID))
        guard !expectedIDs.isEmpty else { return false }

        let payloadID = submission.payloadID
        let contexts = try modelContext.fetch(
            FetchDescriptor<WordImportContext>(
                predicate: #Predicate<WordImportContext> { context in
                    context.submissionPayloadID == payloadID
                }
            )
        )
        let actualIDs = Set<UUID>(
            contexts.compactMap { context -> UUID? in
                guard context.submissionPayloadID == payloadID else { return nil }
                return context.candidatePayloadID
            }
        )
        if expectedIDs.isSubset(of: actualIDs) {
            return true
        }

        // Prior unified-import records had payload identity only in metadata, so
        // candidate UUIDs could not survive backfill. Candidate text plus count
        // identifies those complete transactions safely.
        let expected = normalizedSubmissionCandidates(in: submission)
        let expectedTexts = Set(expected.map(\.text))
        let actualTexts = Set(contexts.compactMap(\.selectedCandidate))
        return contexts.count >= expected.count && expectedTexts.isSubset(of: actualTexts)
    }

    private func normalizedSubmissionCandidates(
        in submission: WordImportSubmission
    ) -> [WordImportCandidatePayload] {
        var ordered: [WordImportCandidatePayload] = []
        var seenKeys = Set<String>()

        for candidate in submission.candidates {
            let normalizedKey = WordInputNormalizer.normalizedKey(from: candidate.text)
                .replacingOccurrences(of: "'", with: "")
            guard !normalizedKey.isEmpty, seenKeys.insert(normalizedKey).inserted else { continue }
            var normalized = candidate
            normalized.normalizedKey = normalizedKey
            ordered.append(normalized)
        }

        return ordered
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
                let key =
                    lookup.result.entry?.normalizedKey
                    ?? WordInputNormalizer.normalizedKey(from: lookup.input.text)

                if let existing = try findEntry(normalizedKey: key) {
                    if lookup.result.status != .notFound,
                        existing.lookupStatus == .notFound || existing.lookupStatus == .userSaved
                    {
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

    @available(*, deprecated, message: "Use importSubmission(_:using:).")
    func addDefaultAppImport(
        _ rawInput: String,
        originalText: String,
        using dictionaryService: any DictionaryLookupService
    ) async throws -> AddWordOutcome {
        let submission = WordImportSubmission(
            source: .defaultApp,
            sourceText: originalText,
            candidates: [
                WordImportCandidatePayload(
                    text: rawInput,
                    normalizedKey: WordInputNormalizer.normalizedKey(from: rawInput)
                )
            ],
            metadata: ["channel": WordImportSource.defaultApp.rawValue]
        )
        let outcomes = try await importSubmission(submission, using: dictionaryService)
        guard let outcome = outcomes.first else { throw WordImportError.emptySelection }
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
        metadata["submittedNormalizedKey"] = input.normalizedKey
        metadata["candidatePayloadID"] = input.payloadID.uuidString
        for (key, value) in submissionMetadata {
            metadata[key] = value
        }
        for (key, value) in input.metadata {
            metadata[key] = value
        }
        metadata["submittedNormalizedKey"] = input.normalizedKey
        metadata["candidatePayloadID"] = input.payloadID.uuidString
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
        if let example = input.userExample, !example.isEmpty {
            metadata["userExample"] = example
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
                submissionPayloadID: payloadID,
                candidatePayloadID: input.payloadID,
                payloadSchemaVersion: schemaVersion,
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
        let translation =
            candidate.userTranslation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let phonetic = candidate.userPhonetic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let example = candidate.userExample?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !translation.isEmpty {
            entry.userTranslation = translation
        }
        if !phonetic.isEmpty {
            entry.phonetic = phonetic
        }
        if !example.isEmpty {
            entry.userExample = example
        }
    }
}

@MainActor
enum WordImportSubmissionMigrator {
    static func processPendingSubmissions(
        baseDirectory base: URL? = nil,
        legacyDefaults: UserDefaults? = nil,
        into modelContext: ModelContext,
        dictionaryService: any DictionaryLookupService
    ) async throws -> WordImportSubmissionMigrationResult {
        let snapshot = try WordImportSubmissionQueue.snapshot(
            baseDirectory: base,
            legacyDefaults: legacyDefaults
        )
        let repository = WordbookRepository(modelContext: modelContext)
        var result = WordImportSubmissionMigrationResult(
            malformedQuarantinedCount: snapshot.malformedCount,
            futureSchemaQuarantinedCount: snapshot.futureSchemaCount
        )

        for submission in snapshot.pending.sorted(by: orderSubmission) {
            if try repository.hasCompletedImport(submission) {
                result.skippedReplayedCount += 1
                try WordImportSubmissionQueue.remove(
                    [submission.payloadID],
                    baseDirectory: base,
                    legacyDefaults: legacyDefaults
                )
                continue
            }

            let outcomes = try await repository.importSubmission(
                submission,
                using: dictionaryService
            )
            result.importedPayloadCount += 1
            result.processedCandidateCount += outcomes.count
            try WordImportSubmissionQueue.remove(
                [submission.payloadID],
                baseDirectory: base,
                legacyDefaults: legacyDefaults
            )
        }

        return result
    }
}

@MainActor
struct WordImportSubmissionMigrationResult: Equatable {
    var importedPayloadCount = 0
    var processedCandidateCount = 0
    var skippedReplayedCount = 0
    var malformedQuarantinedCount = 0
    var futureSchemaQuarantinedCount = 0

    var attentionMessage: String? {
        WordImportSubmissionQueue.attentionMessage(
            for: WordImportQueueSnapshot(
                pending: [],
                malformedCount: malformedQuarantinedCount,
                futureSchemaCount: futureSchemaQuarantinedCount
            )
        )
    }
}

private func orderSubmission(
    _ left: WordImportSubmission,
    _ right: WordImportSubmission
) -> Bool {
    if left.createdAt != right.createdAt {
        return left.createdAt < right.createdAt
    }
    return left.payloadID.uuidString < right.payloadID.uuidString
}

enum WordImportError: Error, Equatable {
    case emptySelection
}

@MainActor
enum WordImportContextMigrator {
    static let backfillCompletedKey = "wordImportContextEntryIDBackfill.v1.completed"
    static let submissionIdentityBackfillCompletedKey =
        "wordImportSubmissionIdentityBackfill.v1.completed"

    static func backfillSubmissionIdentity(
        in modelContext: ModelContext,
        defaults: UserDefaults = .standard,
        save saveAction: ((ModelContext) throws -> Void)? = nil
    ) throws {
        guard !defaults.bool(forKey: submissionIdentityBackfillCompletedKey) else { return }
        let contexts = try modelContext.fetch(FetchDescriptor<WordImportContext>())
        var didChange = false

        for context in contexts where context.submissionPayloadID == nil {
            guard let rawID = context.metadata["payloadID"],
                let payloadID = UUID(uuidString: rawID)
            else { continue }
            context.submissionPayloadID = payloadID
            context.payloadSchemaVersion = context.metadata["payloadSchemaVersion"].flatMap(
                Int.init)
            didChange = true
        }

        guard didChange else {
            defaults.set(true, forKey: submissionIdentityBackfillCompletedKey)
            return
        }
        let performSave = saveAction ?? { context in try context.save() }
        do {
            try performSave(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
        defaults.set(true, forKey: submissionIdentityBackfillCompletedKey)
    }

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

        let performSave =
            saveAction ?? { context in
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
