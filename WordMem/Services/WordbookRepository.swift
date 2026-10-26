import Foundation
import SwiftData

enum AddWordOutcome {
    case added(WordEntry)
    case duplicate(WordEntry)

    var isAdded: Bool {
        if case .added = self { return true }
        return false
    }

    var entry: WordEntry {
        switch self {
        case .added(let entry), .duplicate(let entry): entry
        }
    }
}

enum WordImportError: Error, Equatable {
    case emptySelection
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
        self.saveAction = saveAction ?? { try $0.save() }
    }

    func importSubmission(
        _ submission: WordImportSubmission,
        using dictionary: any AuthoritativeDictionaryAuthorizing
    ) async throws -> [AddWordOutcome] {
        let candidates = validatedCandidates(submission)
        guard !candidates.isEmpty else { throw WordImportError.emptySelection }

        var outcomes: [AddWordOutcome] = []
        var seenIdentities = Set<String>()
        var inserted = false

        for candidate in candidates {
            let identityKey = candidate.normalizedKey.lowercased()
            if candidate.metadata["phraseContext"] == "true" {
                insertContext(
                    entry: nil, candidate: candidate, submission: submission,
                    metadata: candidate.metadata
                )
                inserted = true
                continue
            }

            guard !identityKey.isEmpty, seenIdentities.insert(identityKey).inserted else { continue }
            guard await dictionary.hasDefinition(forTerm: candidate.normalizedKey) else { continue }

            let originalKey = candidate.metadata["originalKey"] ?? candidate.normalizedKey
            let originalAvailable = originalKey == candidate.normalizedKey
                ? true
                : await dictionary.hasDefinition(forTerm: originalKey)
            guard originalAvailable else { continue }

            var metadata = submission.mergedMetadata(for: candidate)
            metadata["canonicalKey"] = candidate.normalizedKey
            metadata["originalKey"] = originalKey

            if let existing = try entry(locale: submission.locale, key: candidate.normalizedKey) {
                apply(candidate, to: existing)
                insertContext(
                    entry: existing, candidate: candidate, submission: submission,
                    metadata: metadata
                )
                outcomes.append(.duplicate(existing))
            } else {
                let entry = WordEntry(
                    localeIdentifier: submission.locale.identifier,
                    normalizedKey: candidate.normalizedKey,
                    headword: candidate.text,
                    originalText: candidate.metadata["originalWord"] ?? candidate.text,
                )
                apply(candidate, to: entry)
                modelContext.insert(entry)
                insertContext(
                    entry: entry, candidate: candidate, submission: submission,
                    metadata: metadata
                )
                outcomes.append(.added(entry))
            }
            inserted = true
        }

        if inserted {
            do { try saveAction(modelContext) }
            catch { modelContext.rollback(); throw error }
        }
        return outcomes
    }

    func hasCompletedImport(_ submission: WordImportSubmission) throws -> Bool {
        let expectedIDs = Set(validatedCandidates(submission).map(\.payloadID))
        guard !expectedIDs.isEmpty else { return false }

        let contexts = try modelContext.fetch(FetchDescriptor<WordImportContext>())
        let actualIDs = Set(contexts.compactMap(\.candidatePayloadID))
        return expectedIDs.isSubset(of: actualIDs)
    }

    func delete(_ entries: [WordEntry]) throws {
        let entryIDs = Set(entries.map(\.id))
        let allContexts = try modelContext.fetch(FetchDescriptor<WordImportContext>())
        for context in allContexts where context.entry == nil || entryIDs.contains(context.entry?.id ?? UUID()) {
            modelContext.delete(context)
        }
        entries.forEach(modelContext.delete)
        do { try saveAction(modelContext) }
        catch { modelContext.rollback(); throw error }
    }

    private func validatedCandidates(
        _ submission: WordImportSubmission
    ) -> [WordImportCandidatePayload] {
        var ordered: [WordImportCandidatePayload] = []
        var seenPayloadIDs = Set<UUID>()

        for candidate in submission.candidates {
            let key = candidate.normalizedKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, seenPayloadIDs.insert(candidate.payloadID).inserted else { continue }
            var preserved = candidate
            preserved.normalizedKey = key
            ordered.append(preserved)
        }
        return ordered
    }

    private func entry(locale: Locale, key: String) throws -> WordEntry? {
        let identifier = locale.identifier
        var descriptor = FetchDescriptor<WordEntry>(
            predicate: #Predicate { $0.localeIdentifier == identifier && $0.normalizedKey == key }
        )
        descriptor.fetchLimit = 1
        descriptor.includePendingChanges = true
        return try modelContext.fetch(descriptor).first
    }

    private func apply(_ candidate: WordImportCandidatePayload, to entry: WordEntry) {
        entry.headword = candidate.text
        if let translation = candidate.userTranslation?.trimmingCharacters(in: .whitespacesAndNewlines), !translation.isEmpty {
            entry.userTranslation = translation
        }
        if let example = candidate.userExample?.trimmingCharacters(in: .whitespacesAndNewlines), !example.isEmpty {
            entry.userExample = example
        }
        if let note = candidate.userNote?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            entry.userNote = note
        }
        entry.updatedAt = .now
    }

    private func insertContext(
        entry: WordEntry?,
        candidate: WordImportCandidatePayload,
        submission: WordImportSubmission,
        metadata: [String: String]
    ) {
        modelContext.insert(
            WordImportContext(
                entry: entry,
                source: submission.source,
                sourceText: submission.sourceText,
                selectedCandidate: candidate.text,
                recognizedText: submission.recognizedText,
                imageData: submission.imageData,
                submissionPayloadID: submission.payloadID,
                candidatePayloadID: candidate.payloadID,
                metadata: metadata
            )
        )
    }
}
