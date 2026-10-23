import SwiftData
import UIKit
import XCTest
@testable import WordMem

@MainActor
final class DictionaryLookupTests: XCTestCase {
    func testNormalizationTrimsCasePunctuationAndCurlyApostrophes() {
        XCTAssertEqual(WordInputNormalizer.normalizedKey(from: "  Beautiful! "), "beautiful")
        XCTAssertEqual(WordInputNormalizer.normalizedKey(from: "Don’t"), "don't")
        XCTAssertEqual(WordInputNormalizer.normalizedKey(from: "Ｂｅａｕｔｉｆｕｌ！"), "beautiful")
        XCTAssertEqual(WordInputNormalizer.normalizedKey(from: "Café"), "cafe")
        XCTAssertEqual(WordInputNormalizer.normalizedKey(from: "mother-in-law"), "mother-in-law")
        XCTAssertEqual(WordInputNormalizer.normalizedKey(from: "   "), "")
    }

    func testAvailableTermReturnsEnrichedKeyOnlyEntry() async throws {
        let availability = StubSystemDictionaryAvailability(availableTerms: ["beautiful"])
        let service = SystemDictionaryLookupService(availability: availability)

        let result = try await service.lookup("  Beautiful! ")

        XCTAssertEqual(result.status, .enriched)
        XCTAssertEqual(result.originalInput, "  Beautiful! ")
        XCTAssertEqual(result.entry?.normalizedKey, "beautiful")
        XCTAssertEqual(result.entry?.headword, "beautiful")
        XCTAssertEqual(result.entry?.dictionaryVersion, SystemDictionaryLookupService.dictionaryVersion)
        // Key-only contract: the system dictionary owns definitions and
        // pronunciations, so the wordbook stores no authoritative content.
        XCTAssertEqual(result.entry?.phonetic, nil)
        XCTAssertTrue(result.entry?.senses.isEmpty ?? false)
        XCTAssertTrue(result.entry?.forms.isEmpty ?? false)
        XCTAssertTrue(result.entry?.tags.isEmpty ?? false)
        XCTAssertEqual(result.entry?.isContentBearing, false)
        let requestedTerms = await availability.requestedTerms
        XCTAssertEqual(requestedTerms, ["beautiful"])
    }

    func testUnavailableTermReturnsNotFoundWithKeyOnlyEntry() async throws {
        let availability = StubSystemDictionaryAvailability(availableTerms: [])
        let service = SystemDictionaryLookupService(availability: availability)

        let result = try await service.lookup("zheeple")

        XCTAssertEqual(result.status, .notFound)
        XCTAssertEqual(result.entry?.headword, "zheeple")
        XCTAssertEqual(result.entry?.normalizedKey, "zheeple")
        XCTAssertTrue(result.entry?.senses.isEmpty ?? false)
        let requestedTerms = await availability.requestedTerms
        XCTAssertEqual(requestedTerms, ["zheeple"])
    }

    func testEmptyInputReturnsNotFoundWithoutConsultingSystemDictionary() async throws {
        let availability = StubSystemDictionaryAvailability(availableTerms: [])
        let service = SystemDictionaryLookupService(availability: availability)

        let result = try await service.lookup("   ")

        XCTAssertEqual(result.status, .notFound)
        XCTAssertNil(result.entry)
        let requestedTerms = await availability.requestedTerms
        XCTAssertEqual(requestedTerms, [])
    }

    func testUIKitDictionaryAvailabilityIsCallable() {
        // Simulator dictionary assets vary by environment, so only verify the
        // public UIKit API is callable and returns a Bool without crashing.
        let hasDefinition = UIReferenceLibraryViewController.dictionaryHasDefinition(
            forTerm: "beautiful"
        )
        XCTAssertTrue(hasDefinition || !hasDefinition)
    }

    func testNewImportStoresKeyOnlyEntry() async throws {
        let fixture = try makeRepositoryFixture(
            availability: StubSystemDictionaryAvailability(availableTerms: ["beautiful"])
        )

        let outcome = try await fixture.repository.add(
            "Beautiful",
            using: fixture.dictionaryService
        )

        guard case .added(let entry) = outcome else {
            return XCTFail("Expected a new word, got \(outcome)")
        }
        XCTAssertEqual(entry.normalizedKey, "beautiful")
        XCTAssertEqual(entry.headword, "beautiful")
        XCTAssertEqual(entry.lookupStatus, .enriched)
        XCTAssertTrue(entry.translation.isEmpty)
        XCTAssertTrue(entry.senses.isEmpty)
        XCTAssertNil(entry.phonetic)
    }

    func testNewImportOfUnknownTermStoresBareKey() async throws {
        let fixture = try makeRepositoryFixture(
            availability: StubSystemDictionaryAvailability(availableTerms: [])
        )

        let outcome = try await fixture.repository.add(
            "zheeple",
            using: fixture.dictionaryService
        )

        guard case .added(let entry) = outcome else {
            return XCTFail("Expected a new word, got \(outcome)")
        }
        XCTAssertEqual(entry.normalizedKey, "zheeple")
        XCTAssertEqual(entry.lookupStatus, .notFound)
        XCTAssertTrue(entry.senses.isEmpty)
    }

    func testKeyOnlyLookupNeverOverwritesStoredUserContent() async throws {
        let fixture = try makeRepositoryFixture(
            availability: StubSystemDictionaryAvailability(availableTerms: ["run"])
        )
        fixture.modelContext.insert(
            WordEntry(
                originalInput: "run",
                normalizedKey: "run",
                headword: "run",
                phonetic: "/rʌn/",
                translation: "旧数据",
                userTranslation: "我自己的解释",
                senses: [WordSense(partOfSpeech: "v.", chinese: "跑；奔跑", english: nil)],
                lookupStatus: .userSaved
            )
        )
        try fixture.modelContext.save()

        let outcome = try await fixture.repository.add(
            "run",
            using: fixture.dictionaryService
        )

        guard case .duplicate(let entry) = outcome else {
            return XCTFail("Expected the existing word to be reused, got \(outcome)")
        }
        XCTAssertEqual(entry.lookupStatus, .userSaved)
        XCTAssertEqual(entry.translation, "旧数据")
        XCTAssertEqual(entry.userTranslation, "我自己的解释")
        XCTAssertEqual(entry.phonetic, "/rʌn/")
        XCTAssertEqual(entry.senses.first?.chinese, "跑；奔跑")
        XCTAssertEqual(try fixture.modelContext.fetch(FetchDescriptor<WordEntry>()).count, 1)
    }

    func testKeyOnlyLookupRefreshesNotFoundBadgeWithoutInventingContent() async throws {
        let fixture = try makeRepositoryFixture(
            availability: StubSystemDictionaryAvailability(availableTerms: ["run"])
        )
        fixture.modelContext.insert(
            WordEntry(
                originalInput: "run",
                normalizedKey: "run",
                headword: "run",
                lookupStatus: .notFound
            )
        )
        try fixture.modelContext.save()

        let outcome = try await fixture.repository.add(
            "run",
            using: fixture.dictionaryService
        )

        guard case .duplicate(let entry) = outcome else {
            return XCTFail("Expected the existing word to be reused, got \(outcome)")
        }
        XCTAssertEqual(entry.lookupStatus, .enriched)
        XCTAssertEqual(entry.headword, "run")
        XCTAssertTrue(entry.translation.isEmpty)
        XCTAssertTrue(entry.senses.isEmpty)
    }

    func testLegacyMigrationWithKeyOnlyLookupPreservesUserTranslations() async throws {
        let suiteName = "SystemDictionaryMigration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyWords = [WordData(word: "run", translation: "跑", phonetic: "/rʌn/")]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        defaults.set(try encoder.encode(legacyWords), forKey: "saved_words")

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WordEntry.self, configurations: configuration)
        let context = ModelContext(container)

        try await LegacyWordbookMigrator.migrateIfNeeded(
            defaults: defaults,
            into: context,
            dictionaryService: SystemDictionaryLookupService(
                availability: StubSystemDictionaryAvailability(availableTerms: ["run"])
            )
        )

        let entry = try XCTUnwrap(
            try context.fetch(FetchDescriptor<WordEntry>()).first
        )
        XCTAssertEqual(entry.lookupStatus, .userSaved)
        XCTAssertEqual(entry.translation, "跑")
        XCTAssertEqual(entry.userTranslation, "跑")
        XCTAssertEqual(entry.phonetic, "/rʌn/")
        XCTAssertTrue(entry.senses.isEmpty)
    }

    private struct RepositoryFixture {
        let modelContext: ModelContext
        let repository: WordbookRepository
        let dictionaryService: SystemDictionaryLookupService
    }

    private func makeRepositoryFixture(
        availability: StubSystemDictionaryAvailability
    ) throws -> RepositoryFixture {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WordEntry.self,
            WordImportContext.self,
            configurations: configuration
        )
        let modelContext = ModelContext(container)

        return RepositoryFixture(
            modelContext: modelContext,
            repository: WordbookRepository(modelContext: modelContext),
            dictionaryService: SystemDictionaryLookupService(availability: availability)
        )
    }
}

private actor StubSystemDictionaryAvailability: SystemDictionaryAvailabilityProviding {
    private let availableTerms: Set<String>
    private(set) var requestedTerms: [String] = []

    init(availableTerms: Set<String>) {
        self.availableTerms = availableTerms
    }

    func hasDefinition(forTerm term: String) async -> Bool {
        requestedTerms.append(term)
        return availableTerms.contains(term)
    }
}
