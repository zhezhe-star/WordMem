import SwiftData
import UIKit
import XCTest

@testable import WordMem

@MainActor
final class CanonicalCleanResetTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private let suiteName = "CanonicalCleanReset.\(UUID().uuidString)"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CanonicalCleanReset-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeContext() throws -> ModelContext {
        let store = WordMemStore(storeURL: directory.appendingPathComponent("v3.store"), defaults: defaults)
        let container = try store.makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    func testFreshStoreStartsEmptyAndUsesLocalePlusKeyIdentity() async throws {
        let context = try makeContext()
        let repository = WordbookRepository(modelContext: context)
        let identity = WordIdentity(locale: Locale(identifier: "en_US_POSIX"), key: "give")
        XCTAssertEqual(identity.locale.identifier, "en_US_POSIX")
        XCTAssertEqual(identity.key, "give")
        let entries = try context.fetch(FetchDescriptor<WordEntry>())
        XCTAssertTrue(entries.isEmpty)
    }

    func testDifferentLocalesDoNotCollide() throws {
        let context = try makeContext()
        context.insert(WordEntry(
            localeIdentifier: "en_US_POSIX", normalizedKey: "give", headword: "give", originalText: "give"
        ))
        context.insert(WordEntry(
            localeIdentifier: "en_GB", normalizedKey: "give", headword: "give", originalText: "give"
        ))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<WordEntry>()).count, 2)
    }

    func testAdvisorCanonicalKeysSurviveAndRevalidateAgainstAuthoritativeDictionary() async throws {
        let context = try makeContext()
        let repository = WordbookRepository(modelContext: context)
        let dictionary = FixedAuthoritativeDictionary(available: ["give", "receive"])

        let gave = WordImportCandidatePayload(
            payloadID: UUID(), text: "gave", normalizedKey: "give",
            metadata: ["originalWord": "gave", "lemma": "give"]
        )
        let receive = WordImportCandidatePayload(
            payloadID: UUID(), text: "recieve", normalizedKey: "receive",
            metadata: ["originalWord": "recieve", "spellingCorrection": "receive"]
        )
        let submission = WordImportSubmission(
            source: .text, sourceText: "gave recieve",
            candidates: [gave, receive]
        )
        let outcomes = try await repository.importSubmission(submission, using: dictionary)

        XCTAssertEqual(outcomes.map(\.isAdded), [true, true])
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<WordEntry>()).map(\.normalizedKey).sorted(),
            ["give", "receive"]
        )
        let metadata = try context.fetch(FetchDescriptor<WordImportContext>())
            .compactMap { $0.metadata["canonicalKey"] }
        XCTAssertEqual(Set(metadata), ["give", "receive"])
    }

    func testUnavailableFinalAndRestoredCandidatesAreSkippedWithoutRecomputingAdvisorKey() async throws {
        let context = try makeContext()
        let repository = WordbookRepository(modelContext: context)
        let dictionary = FixedAuthoritativeDictionary(available: [])

        let unavailable = WordImportCandidatePayload(
            payloadID: UUID(), text: "blurble", normalizedKey: "definitelyadvisorkey"
        )
        let restored = WordImportCandidatePayload(
            payloadID: UUID(), text: "blurble", normalizedKey: "restoredadvisorkey",
            metadata: ["originalWord": "orig", "originalKey": "restoredadvisorkey"]
        )
        let submission = WordImportSubmission(
            source: .manual, sourceText: "blurble", candidates: [unavailable, restored]
        )
        let outcomes = try await repository.importSubmission(submission, using: dictionary)
        XCTAssertTrue(outcomes.isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WordEntry>()).isEmpty)
    }

    func testSameCanonicalKeyAddsThenDeduplicatesWithStableReplay() async throws {
        let context = try makeContext()
        let repository = WordbookRepository(modelContext: context)
        let dictionary = FixedAuthoritativeDictionary(available: ["give"])
        let payloadID = UUID()

        let first = WordImportSubmission(
            source: .text, sourceText: "gave",
            candidates: [WordImportCandidatePayload(payloadID: payloadID, text: "gave", normalizedKey: "give")]
        )
        let replay = WordImportSubmission(
            payloadID: UUID(), source: .text, sourceText: "gave",
            candidates: [WordImportCandidatePayload(payloadID: payloadID, text: "gave", normalizedKey: "give")]
        )
        let firstOutcomes = try await repository.importSubmission(first, using: dictionary)
        let replayOutcomes = try await repository.importSubmission(replay, using: dictionary)

        XCTAssertEqual(firstOutcomes.first?.isAdded, true)
        XCTAssertEqual(replayOutcomes.first?.isAdded, false)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WordEntry>()).count, 1)
        XCTAssertTrue(try repository.hasCompletedImport(replay))
    }

    func testDeleteRemovesOrphanedPhraseContexts() async throws {
        let context = try makeContext()
        let repository = WordbookRepository(modelContext: context)
        let entry = WordEntry(normalizedKey: "give", headword: "give", originalText: "give")
        context.insert(entry)
        try context.save()
        let phrase = WordImportCandidatePayload(
            payloadID: UUID(), text: "solid rock", normalizedKey: "solid-rock",
            metadata: ["phraseContext": "true"]
        )
        _ = try await repository.importSubmission(
            WordImportSubmission(source: .text, sourceText: "solid rock", candidates: [phrase]),
            using: FixedAuthoritativeDictionary(available: [])
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<WordImportContext>()).count, 1)

        try repository.delete([entry])

        XCTAssertTrue(try context.fetch(FetchDescriptor<WordEntry>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WordImportContext>()).isEmpty)
    }

    func testPhraseContextIsStoredSeparatelyFromWordEntry() async throws {
        let context = try makeContext()
        let repository = WordbookRepository(modelContext: context)
        let phrase = WordImportCandidatePayload(
            payloadID: UUID(), text: "solid rock", normalizedKey: "solid-rock",
            metadata: ["phraseContext": "true"]
        )
        let submission = WordImportSubmission(source: .text, sourceText: "solid rock", candidates: [phrase])
        let outcomes = try await repository.importSubmission(
            submission, using: FixedAuthoritativeDictionary(available: [])
        )
        XCTAssertTrue(outcomes.isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WordEntry>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WordImportContext>()).first?.selectedCandidate, "solid rock")
    }

    func testDestructiveResetRemovesHistoricalStoreFilesAndQueueDefaults() throws {
        let historical = directory.appendingPathComponent("historical.store")
        try Data("historical".utf8).write(to: historical)
        let queueDirectory = directory.appendingPathComponent("WordMemImportQueue", isDirectory: true)
        try FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
        try Data("queue".utf8).write(to: queueDirectory.appendingPathComponent("submission.json"))
        defaults.set(Data("historical".utf8), forKey: "saved_words")
        defaults.set(Data("queue".utf8), forKey: "pending_word_import_submissions.v1")

        _ = WordMemStore(
            storeURL: directory.appendingPathComponent("v3.store"),
            defaults: defaults,
            legacyStoreURL: historical,
            legacyQueueDirectory: queueDirectory
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: historical.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: queueDirectory.path))
        XCTAssertNil(defaults.data(forKey: "saved_words"))
        XCTAssertNil(defaults.data(forKey: "pending_word_import_submissions.v1"))
        XCTAssertEqual(defaults.integer(forKey: "wordmem.destructiveResetVersion"), 3)
        XCTAssertFalse(defaults.bool(forKey: "wordmem.nativeStoreV3.resetCompleted"))
    }

    func testSchemaResetDeletesStoresCompletedByPreviousReset() throws {
        let store = directory.appendingPathComponent("v2-schema.store")
        try Data("schema v2".utf8).write(to: store)
        defaults.set(2, forKey: "wordmem.destructiveResetVersion")

        _ = WordMemStore(
            storeURL: store,
            defaults: defaults,
            legacyStoreURL: nil,
            legacyQueueDirectory: nil
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.path))
        XCTAssertEqual(defaults.integer(forKey: "wordmem.destructiveResetVersion"), 3)
    }

    func testCustomStoreResetDoesNotDeleteProductionDefaultStore() throws {
        let defaultStore = directory.appendingPathComponent("default.store")
        try Data("default".utf8).write(to: defaultStore)
        _ = WordMemStore(
            storeURL: directory.appendingPathComponent("custom.store"),
            defaults: defaults,
            legacyStoreURL: nil,
            legacyQueueDirectory: nil
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: defaultStore.path))
    }

    func testPersistentModelSurfaceContainsOnlyUserAndIdentityFields() throws {
        let names = Set(Mirror(reflecting: WordEntry(
            normalizedKey: "give", headword: "give", originalText: "gave"
        )).children.compactMap(\.label)
            .map { $0.hasPrefix("_") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty && !$0.hasPrefix("$") })
        let expected: Set<String> = [
            "id", "localeIdentifier", "normalizedKey", "headword", "originalText",
            "userTranslation", "userExample", "userNote",
            "createdAt", "updatedAt",
        ]
        XCTAssertEqual(names, expected)
    }

    func testAuthoritativeProviderReturnsStructuredWordNetEntry() async throws {
        let provider = WordNetKitAuthoritativeDictionaryProvider()

        let entry = try await provider.entry(forTerm: "dog")

        XCTAssertEqual(entry?.providerID, "org.globalwordnet.oewn")
        XCTAssertEqual(entry?.providerRevision, "2025")
        XCTAssertEqual(entry?.license, "CC-BY-4.0")
        XCTAssertEqual(entry?.canonicalKey, "dog")
        XCTAssertEqual(entry?.headword, "dog")
        XCTAssertFalse(entry?.senses.isEmpty ?? true)
        XCTAssertEqual(entry?.senses.first?.partOfSpeech, "noun")
        XCTAssertFalse(entry?.senses.first?.definition.isEmpty ?? true)
        XCTAssertFalse(entry?.pronunciations.isEmpty ?? true)
    }

    func testAuthoritativeProviderHasDefinitionAndOmitsUnknownTerms() async throws {
        let provider = WordNetKitAuthoritativeDictionaryProvider()

        let available = await provider.hasDefinition(forTerm: "dog")
        let unavailable = await provider.hasDefinition(forTerm: "wordmemnotaword")
        let missing = try await provider.entry(forTerm: "wordmemnotaword")

        XCTAssertTrue(available)
        XCTAssertFalse(unavailable)
        XCTAssertNil(missing)
    }

    func testCalendarUsesOnlyEntriesWithUserTranslation() throws {
        let context = try makeContext()
        context.insert(WordEntry(
            normalizedKey: "give", headword: "give", originalText: "give", userTranslation: "给"
        ))
        context.insert(WordEntry(normalizedKey: "take", headword: "take", originalText: "take"))
        try context.save()

        let words = try context.fetch(FetchDescriptor<WordEntry>()).compactMap(\.calendarWord)
        XCTAssertEqual(words.map(\.word), ["give"])
        XCTAssertEqual(words.first?.translation, "给")
    }

    func testCandidateSelectionDefaultsToNone() {
        let chip = ImportCandidateChip(id: "give", text: "give", sourceOrder: 0)
        let selection = ImportChipSelection(chips: [chip])
        XCTAssertEqual(selection.selectedCount, 0)
    }

    func testCandidatePayloadOmitsDerivedDictionaryAvailability() {
        let advice = ImportWordAdvice(
            originalText: "gave", originalKey: "gave", context: nil, lemma: "give",
            spellingCorrection: nil, finalText: "give", finalKey: "give",
            isDictionaryAvailable: true, isOriginalDictionaryAvailable: true
        )
        let chip = ImportCandidateChip(id: "give", text: "give", sourceOrder: 0, advice: advice)

        let payload = ImportCandidatePipeline.payload(from: chip)

        XCTAssertNil(payload.metadata["dictionaryAvailable"])
        XCTAssertNil(payload.metadata["originalDictionaryAvailable"])
    }

    func testLegacySwiftDataStorePathIsSeparatedFromNativeV3Store() {
        let legacy = WordMemStore.legacySwiftDataStoreURL
        XCTAssertEqual(legacy.lastPathComponent, "default.store")
        XCTAssertEqual(legacy.deletingLastPathComponent().lastPathComponent, "Application Support")
        XCTAssertNotEqual(legacy, WordMemStore.defaultStoreURL)
    }

    func testOCRSanitizerRemovesStatusBarAndSymbolOnlyLines() {
        let raw = """
        12:32
        :!.. 5GA
        87
        --

        The experiment measured steady growth.
        The 5G network remained stable.
        serendipity
        15:04
        754?
        <
        Φb}...
        Daily recap...
        """
        let sanitized = OCRTextSanitizer.sanitizedLines(from: raw)
        XCTAssertEqual(
            sanitized,
            [
                "The experiment measured steady growth.",
                "The 5G network remained stable.",
                "serendipity",
                "Daily recap...",
            ]
        )

        let rawTokens = EnglishWordCandidateSplitter.candidates(from: raw).map(\.normalizedKey)
        let cleanTokens = EnglishWordCandidateSplitter.candidates(
            from: sanitized.joined(separator: "\n")
        ).map(\.normalizedKey)
        XCTAssertFalse(rawTokens.isEmpty)
        XCTAssertNotEqual(rawTokens, cleanTokens)
    }
}

private struct FixedAuthoritativeDictionary: AuthoritativeDictionaryAuthorizing {
    let available: Set<String>

    func hasDefinition(forTerm term: String) async -> Bool {
        available.contains(term)
    }

    func entry(forTerm term: String) async throws -> AuthoritativeDictionaryEntry? {
        available.contains(term) ? AuthoritativeDictionaryEntry(
            providerID: "test",
            providerRevision: "1",
            license: "test",
            canonicalKey: term,
            headword: term,
            pronunciations: [],
            senses: []
        ) : nil
    }
}
