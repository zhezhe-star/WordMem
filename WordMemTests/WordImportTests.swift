import SwiftData
import XCTest
@testable import WordMem

@MainActor
final class WordImportTests: XCTestCase {
    private struct Fixture {
        let modelContext: ModelContext
        let repository: WordbookRepository
        let dictionaryService: BundledDictionaryLookupService
    }

    private func makeFixture() throws -> Fixture {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WordEntry.self,
            WordImportContext.self,
            configurations: configuration
        )
        let modelContext = ModelContext(container)

        return Fixture(
            modelContext: modelContext,
            repository: WordbookRepository(modelContext: modelContext),
            dictionaryService: BundledDictionaryLookupService(
                catalog: DevelopmentSeedDictionaryCatalog.entries
            )
        )
    }

    func testCandidateSplittingKeepsEnglishWordsInOrderAndDeduplicatesByMeaning() {
        let candidates = EnglishWordCandidateSplitter.candidates(
            from: "The cat saw two cats; it didn't blink!"
        )

        XCTAssertEqual(candidates.map(\.text), ["The", "cat", "saw", "two", "cats", "it", "didn't", "blink"])
        XCTAssertEqual(candidates.map(\.normalizedKey), [
            "the", "cat", "saw", "two", "cats", "it", "didnt", "blink",
        ])
        XCTAssertTrue(candidates.allSatisfy(\.isSelected))
    }

    func testTextBatchImportCreatesSelectedWordsWithSharedSourceSentence() async throws {
        let fixture = try makeFixture()
        let sourceSentence = "The quick brown fox jumps over the lazy dog."

        let outcomes = try await fixture.repository.importWords(
            ["quick", "fox", "quick"],
            source: .text,
            sourceText: sourceSentence,
            using: fixture.dictionaryService
        )

        XCTAssertEqual(outcomes.count, 2)
        XCTAssertEqual(outcomes.map(\.entry.headword), ["quick", "fox"])

        let entries = try fixture.modelContext.fetch(FetchDescriptor<WordEntry>())
        let contexts = try fixture.modelContext.fetch(FetchDescriptor<WordImportContext>())
        XCTAssertEqual(entries.map(\.normalizedKey).sorted(), ["fox", "quick"])
        XCTAssertEqual(contexts.count, 2)
        XCTAssertTrue(contexts.allSatisfy { $0.source == .text })
        XCTAssertTrue(contexts.allSatisfy { $0.sourceText == sourceSentence })
        XCTAssertEqual(
            Set(contexts.map(\.selectedCandidate)),
            ["quick", "fox"]
        )
    }

    func testDuplicateImportAttachesNewContextAndKeepsPriorHistory() async throws {
        let fixture = try makeFixture()
        _ = try await fixture.repository.importWords(
            ["run"],
            source: .text,
            sourceText: "I run every morning.",
            using: fixture.dictionaryService
        )

        let duplicateOutcomes = try await fixture.repository.importWords(
            ["running"],
            source: .defaultApp,
            sourceText: "Running is healthy.",
            using: fixture.dictionaryService
        )

        guard case .duplicate = duplicateOutcomes.first else {
            return XCTFail("Expected lemma lookup to reuse run, got \(String(describing: duplicateOutcomes.first))")
        }

        let entries = try fixture.modelContext.fetch(FetchDescriptor<WordEntry>())
        let contexts = try fixture.modelContext.fetch(FetchDescriptor<WordImportContext>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.normalizedKey, "run")
        XCTAssertEqual(contexts.count, 2)
        XCTAssertEqual(
            Set(contexts.map(\.sourceText)),
            ["I run every morning.", "Running is healthy."]
        )
        XCTAssertEqual(contexts.map(\.source), [.text, .defaultApp])
    }

    func testImageImportStoresImageDataAndRecognizedText() async throws {
        let fixture = try makeFixture()
        let imageData = Data([0x89, 0x50, 0x4e, 0x47])
        let recognizedText = "Beautiful mountain"

        let outcomes = try await fixture.repository.importWords(
            ["beautiful", "mountain"],
            source: .image,
            sourceText: recognizedText,
            imageData: imageData,
            recognizedText: recognizedText,
            using: fixture.dictionaryService
        )

        XCTAssertEqual(outcomes.count, 2)
        let contexts = try fixture.modelContext.fetch(FetchDescriptor<WordImportContext>())
        XCTAssertEqual(contexts.count, 2)
        XCTAssertTrue(contexts.allSatisfy { $0.imageData == imageData })
        XCTAssertTrue(contexts.allSatisfy { $0.recognizedText == recognizedText })
        XCTAssertTrue(contexts.allSatisfy { $0.source == .image })
        XCTAssertTrue(contexts.allSatisfy { $0.metadata["imageByteCount"] == "\(imageData.count)" })
    }

    func testDefaultAppImportPersistsOriginalTextAsContext() async throws {
        let fixture = try makeFixture()
        let originalText = "The user selected serendipity while reading."

        let outcome = try await fixture.repository.addDefaultAppImport(
            "serendipity",
            originalText: originalText,
            using: fixture.dictionaryService
        )

        guard case .added = outcome else {
            return XCTFail("Expected a new default-app word, got \(outcome)")
        }

        let contexts = try fixture.modelContext.fetch(FetchDescriptor<WordImportContext>())
        XCTAssertEqual(contexts.count, 1)
        XCTAssertEqual(contexts.first?.source, .defaultApp)
        XCTAssertEqual(contexts.first?.sourceText, originalText)
    }

    func testManualImportRetainsDictionaryLookupAndRecordsSource() async throws {
        let fixture = try makeFixture()

        let outcome = try await fixture.repository.add("gave", using: fixture.dictionaryService)

        guard case .added(let entry) = outcome else {
            return XCTFail("Expected a new word, got \(outcome)")
        }

        XCTAssertEqual(entry.headword, "give")
        XCTAssertEqual(entry.lookupStatus, .lemmaResolved)
        let contexts = try fixture.modelContext.fetch(FetchDescriptor<WordImportContext>())
        XCTAssertEqual(contexts.count, 1)
        XCTAssertEqual(contexts.first?.source, .manual)
    }

    func testUndoAddAlsoRemovesImportContext() async throws {
        let fixture = try makeFixture()
        guard case .added(let entry) = try await fixture.repository.add(
            "run",
            using: fixture.dictionaryService
        ) else {
            return XCTFail("Expected a new word")
        }

        try fixture.repository.undoAdd(entry)

        XCTAssertEqual(try fixture.modelContext.fetch(FetchDescriptor<WordEntry>()).count, 0)
        XCTAssertEqual(try fixture.modelContext.fetch(FetchDescriptor<WordImportContext>()).count, 0)
    }

    func testDeleteWordsAlsoRemovesImportContexts() async throws {
        let fixture = try makeFixture()
        let outcomes = try await fixture.repository.importWords(
            ["run", "fox"],
            source: .text,
            sourceText: "The fox can run.",
            using: fixture.dictionaryService
        )

        try fixture.repository.deleteWords(outcomes.map(\.entry))

        XCTAssertEqual(try fixture.modelContext.fetch(FetchDescriptor<WordEntry>()).count, 0)
        XCTAssertEqual(try fixture.modelContext.fetch(FetchDescriptor<WordImportContext>()).count, 0)
    }

    func testExistingSwiftDataStoreOpensWithImportContextSchema() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WordMemImportMigration-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let originalConfiguration = ModelConfiguration(url: storeURL)
        let originalContainer = try ModelContainer(
            for: Schema([WordEntry.self]),
            configurations: originalConfiguration
        )
        let originalContext = ModelContext(originalContainer)
        originalContext.insert(
            WordEntry(
                originalInput: "run",
                normalizedKey: "run",
                headword: "run"
            )
        )
        try originalContext.save()

        let upgradedConfiguration = ModelConfiguration(url: storeURL)
        let upgradedContainer = try ModelContainer(
            for: Schema([WordEntry.self, WordImportContext.self]),
            configurations: upgradedConfiguration
        )
        let upgradedContext = ModelContext(upgradedContainer)
        let entries = try upgradedContext.fetch(FetchDescriptor<WordEntry>())

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.normalizedKey, "run")
    }

    func testBatchImportFailureDoesNotLeaveNewWordsOrContexts() async throws {
        let fixture = try makeFixture()
        let failingService = ThrowingDictionaryLookupService()

        do {
            _ = try await fixture.repository.importWords(
                ["quick", "fox"],
                source: .text,
                sourceText: "The quick fox.",
                using: failingService
            )
            XCTFail("Expected import to throw")
        } catch {
            XCTAssertEqual(error as? WordImportTestError, .lookupFailed)
        }

        XCTAssertEqual(try fixture.modelContext.fetch(FetchDescriptor<WordEntry>()).count, 0)
        XCTAssertEqual(try fixture.modelContext.fetch(FetchDescriptor<WordImportContext>()).count, 0)
    }

    func testImportSummaryDescribesAddedAndDuplicateCountsInChinese() {
        let existing = WordEntry(
            originalInput: "run",
            normalizedKey: "run",
            headword: "run"
        )
        let created = WordEntry(
            originalInput: "fox",
            normalizedKey: "fox",
            headword: "fox"
        )
        let summary = WordImportSummary(outcomes: [.added(created), .duplicate(existing)])

        XCTAssertEqual(summary.addedCount, 1)
        XCTAssertEqual(summary.duplicateCount, 1)
        XCTAssertEqual(summary.message, "已添加 1 个单词，已有 1 个单词。")
    }
}

private enum WordImportTestError: Error, Equatable {
    case lookupFailed
}

private struct ThrowingDictionaryLookupService: DictionaryLookupService {
    func lookup(_ rawInput: String) async throws -> DictionaryLookupResult {
        throw WordImportTestError.lookupFailed
    }
}
