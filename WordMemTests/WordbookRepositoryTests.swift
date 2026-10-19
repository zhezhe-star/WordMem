import SwiftData
import XCTest
@testable import WordMem

@MainActor
final class WordbookRepositoryTests: XCTestCase {
    private struct Fixture {
        let container: ModelContainer
        let modelContext: ModelContext
        let repository: WordbookRepository
        let dictionaryService: BundledDictionaryLookupService
    }

    private func makeFixture() throws -> Fixture {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WordEntry.self, configurations: configuration)
        let modelContext = ModelContext(container)

        return Fixture(
            container: container,
            modelContext: modelContext,
            repository: WordbookRepository(modelContext: modelContext),
            dictionaryService: BundledDictionaryLookupService(
            catalog: DevelopmentSeedDictionaryCatalog.entries
        )
        )
    }

    func testAddEnrichesLemmaAndPersistsInContext() async throws {
        let fixture = try makeFixture()
        let outcome = try await fixture.repository.add("gave", using: fixture.dictionaryService)

        guard case .added(let entry) = outcome else {
            return XCTFail("Expected a new word, got \(outcome)")
        }

        XCTAssertEqual(entry.headword, "give")
        XCTAssertEqual(entry.originalInput, "gave")
        XCTAssertEqual(entry.lookupStatus, .lemmaResolved)
        XCTAssertEqual(entry.senses.first?.chinese, "给；交给")

        let stored = try fixture.modelContext.fetch(FetchDescriptor<WordEntry>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.normalizedKey, "give")
    }

    func testDuplicateInputDoesNotCreateSecondEntry() async throws {
        let fixture = try makeFixture()
        _ = try await fixture.repository.add("Beautiful", using: fixture.dictionaryService)
        let duplicateOutcome = try await fixture.repository.add(
            "beautiful!",
            using: fixture.dictionaryService
        )

        guard case .duplicate(let entry) = duplicateOutcome else {
            return XCTFail("Expected duplicate, got \(duplicateOutcome)")
        }

        XCTAssertEqual(entry.headword, "beautiful")
        XCTAssertEqual(
            try fixture.modelContext.fetch(FetchDescriptor<WordEntry>()).count,
            1
        )
    }

    func testDuplicateEnrichesExistingBareEntryWithoutCreatingSecondEntry() async throws {
        let fixture = try makeFixture()
        fixture.modelContext.insert(
            WordEntry(
                originalInput: "Run",
                normalizedKey: "run",
                headword: "Run",
                translation: "旧数据",
                lookupStatus: .notFound
            )
        )
        try fixture.modelContext.save()

        let outcome = try await fixture.repository.add("running", using: fixture.dictionaryService)

        guard case .duplicate(let entry) = outcome else {
            return XCTFail("Expected the existing word to be reused, got \(outcome)")
        }

        XCTAssertEqual(entry.headword, "run")
        XCTAssertEqual(entry.lookupStatus, .lemmaResolved)
        XCTAssertEqual(entry.senses.first?.chinese, "跑；奔跑")
        XCTAssertEqual(try fixture.modelContext.fetch(FetchDescriptor<WordEntry>()).count, 1)
    }

    func testUndoAddRemovesOnlyCreatedEntry() async throws {
        let fixture = try makeFixture()
        guard case .added(let entry) = try await fixture.repository.add(
            "run",
            using: fixture.dictionaryService
        ) else {
            return XCTFail("Expected a new word")
        }

        try fixture.repository.undoAdd(entry)

        XCTAssertEqual(
            try fixture.modelContext.fetch(FetchDescriptor<WordEntry>()).count,
            0
        )
    }
}

@MainActor
final class LegacyWordbookMigrationTests: XCTestCase {
    func testExistingUserDefaultsWordsMigrateOnceIntoSwiftData() async throws {
        let suiteName = "WordMemMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyWords = [
            WordData(
                word: "serendipity",
                translation: "我自己的解释",
                phonetic: "/ˌserənˈdɪpəti/",
                example: "supplementary example",
                exampleSentence: "my saved sentence",
                translatedExampleSentence: "我保存的句子翻译"
            ),
            WordData(word: "Run", translation: "跑", phonetic: "/rʌn/"),
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let sourceData = try encoder.encode(legacyWords)
        defaults.set(sourceData, forKey: "saved_words")

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WordEntry.self, configurations: configuration)
        let context = ModelContext(container)

        try LegacyWordbookMigrator.migrateIfNeeded(defaults: defaults, into: context)
        try LegacyWordbookMigrator.migrateIfNeeded(defaults: defaults, into: context)

        let entries = try context.fetch(FetchDescriptor<WordEntry>())
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(Set(entries.map(\.headword)), ["serendipity", "Run"])
        XCTAssertTrue(entries.allSatisfy { $0.lookupStatus == .notFound })
        XCTAssertTrue(defaults.data(forKey: "saved_words.backup.beforeSwiftDataMigration") == sourceData)
        XCTAssertTrue(defaults.bool(forKey: LegacyWordbookMigrator.migrationKey))

        let migratedWord = try XCTUnwrap(entries.first { $0.normalizedKey == "serendipity" })
        XCTAssertEqual(migratedWord.userTranslation, "我自己的解释")
        XCTAssertEqual(migratedWord.legacyExample, "supplementary example")
        XCTAssertEqual(migratedWord.legacyExampleSentence, "my saved sentence")
        XCTAssertEqual(migratedWord.legacyTranslatedExampleSentence, "我保存的句子翻译")

        let enrichedResult = try await BundledDictionaryLookupService().lookup("run")
        try XCTUnwrap(entries.first { $0.normalizedKey == "run" }).apply(enrichedResult)

        let enrichedWord = try XCTUnwrap(entries.first { $0.normalizedKey == "run" })
        XCTAssertEqual(enrichedWord.userTranslation, "跑")
        XCTAssertEqual(enrichedWord.translation, "跑；奔跑")
        XCTAssertEqual(enrichedWord.headword, "run")
    }
}

@MainActor
final class AddWordFeedbackTests: XCTestCase {
    func testDuplicateFeedbackCannotUndoExistingWord() {
        let outcome = AddWordOutcome.duplicate(
            WordEntry(originalInput: "run", normalizedKey: "run", headword: "run")
        )
        let feedback = AddWordFeedback(outcome)

        XCTAssertFalse(feedback.canUndo)
        XCTAssertEqual(feedback.message, "已在单词本 run")
    }

    func testAddedFeedbackCanUndoCreatedWord() {
        let outcome = AddWordOutcome.added(
            WordEntry(originalInput: "run", normalizedKey: "run", headword: "run")
        )
        let feedback = AddWordFeedback(outcome)

        XCTAssertTrue(feedback.canUndo)
        XCTAssertEqual(feedback.message, "已添加 run")
    }
}
