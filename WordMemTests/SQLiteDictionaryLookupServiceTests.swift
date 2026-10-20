import XCTest
@testable import WordMem

final class SQLiteDictionaryLookupServiceTests: XCTestCase {
    private var service: SQLiteDictionaryLookupService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        service = try SQLiteDictionaryLookupService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    func testBundledResourceExistsWithinSizeBudget() async throws {
        let url = try XCTUnwrap(SQLiteDictionaryLookupService.databaseURL())
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        let metadata = try await SQLiteDictionaryLookupService.metadata()

        XCTAssertLessThanOrEqual(size ?? .max, 25 * 1024 * 1024)
        XCTAssertEqual(metadata["selection"], "learner tags or frequency <= 50000")
        XCTAssertEqual(metadata["sourceLicense"], "MIT")
        XCTAssertEqual(metadata["schemaVersion"], "1")
        XCTAssertEqual(metadata["entryCount"], "57838")
        XCTAssertEqual(metadata["lemmaCount"], "49564")
        XCTAssertEqual(metadata["wordFormCount"], "49832")
        XCTAssertEqual(metadata["pipelineVersion"], "3")
        XCTAssertEqual(metadata["curatedLemmaPriorityKeys"], "running")
        XCTAssertNotEqual(metadata["sourceRevision"], "unknown")
        XCTAssertFalse(metadata["sourceCsvSHA256"]?.isEmpty ?? true)
        XCTAssertFalse(metadata["sourceLemmaSHA256"]?.isEmpty ?? true)
    }

    func testExactLookupParsesECDICTEntry() async throws {
        let result = try await service.lookup("Beautiful")

        XCTAssertEqual(result.status, .enriched)
        XCTAssertEqual(
            result.entry?.headword,
            "beautiful",
            "suggestions: \(result.suggestions.map(\.normalizedKey).prefix(10))"
        )
        XCTAssertEqual(result.entry?.normalizedKey, "beautiful")
        XCTAssertFalse(result.entry?.senses.isEmpty ?? true)
        XCTAssertTrue(result.suggestions.isEmpty)
    }

    func testFrequentStandaloneWordsKeepExactEntries() async throws {
        for word in [
            "number", "yes", "saw", "left", "meeting", "best",
            "painting", "meaning", "beginning", "understanding",
            "teaching", "setting", "wedding",
        ] {
            let result = try await service.lookup(word)
            XCTAssertEqual(result.status, .enriched, "\(word) should remain a standalone entry")
            XCTAssertEqual(result.entry?.headword, word)
        }
    }

    func testMorphologicalInflectionsResolveToCanonicalEntry() async throws {
        let running = try await service.lookup("running")
        XCTAssertEqual(running.status, .lemmaResolved)
        XCTAssertEqual(running.entry?.headword, "run")

        let teeth = try await service.lookup("teeth")
        XCTAssertEqual(teeth.status, .lemmaResolved)
        XCTAssertEqual(teeth.entry?.headword, "tooth")
    }

    func testLemmaLookupResolvesInflectionToCanonicalEntry() async throws {
        let result = try await service.lookup("gave")

        XCTAssertEqual(result.status, .lemmaResolved)
        XCTAssertEqual(result.entry?.headword, "give")
        XCTAssertEqual(result.originalInput, "gave")
        XCTAssertTrue(result.entry?.forms.contains { $0.value == "gave" } ?? false)
    }

    func testIrregularPluralResolvesToCanonicalEntry() async throws {
        let result = try await service.lookup("teeth")

        XCTAssertEqual(result.status, .lemmaResolved)
        XCTAssertEqual(result.entry?.headword, "tooth")
        XCTAssertTrue(result.entry?.forms.contains { $0.value == "teeth" } ?? false)
    }

    func testCloseMatchReturnsHighConfidenceCorrection() async throws {
        let result = try await service.lookup("beutiful")

        XCTAssertEqual(result.status, .autoCorrected)
        XCTAssertEqual(result.entry?.headword, "beautiful")
    }

    func testUnknownInputReturnsBareEntryAndSuggestions() async throws {
        let result = try await service.lookup("zheeple")

        XCTAssertEqual(result.status, .notFound)
        XCTAssertEqual(result.entry?.headword, "zheeple")
        XCTAssertTrue(result.entry?.senses.isEmpty ?? false)
    }

    func testEmptyInputReturnsNotFoundWithoutEntry() async throws {
        let result = try await service.lookup("   ")

        XCTAssertEqual(result.status, .notFound)
        XCTAssertNil(result.entry)
    }

    func testBareFallbackServiceAlwaysCapturesUserWord() async throws {
        let service = BareWordDictionaryLookupService()
        let result = try await service.lookup("zheeple")

        XCTAssertEqual(result.status, .notFound)
        XCTAssertNil(result.entry)
    }

    func testInvalidDatabaseResourceThrowsInsteadOfSilentFailure() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WordMem-invalid-\(UUID().uuidString).sqlite")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try SQLiteDictionaryLookupService(databaseURL: url)
            XCTFail("Expected invalid resource to throw")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func testFrequentLookupPerformance() async throws {
        _ = try await service.lookup("beautiful")
        let started = Date()
        let iterations = 100

        for _ in 0..<iterations {
            _ = try await service.lookup("beautiful")
            _ = try await service.lookup("gave")
        }

        let elapsed = Date().timeIntervalSince(started) / Double(iterations * 2)
        XCTAssertLessThan(elapsed, 0.030, "Average exact/lemma lookup took \(elapsed * 1000) ms")
    }

    func testCloseMatchLookupPerformance() async throws {
        _ = try await service.lookup("beutiful")
        let started = Date()
        let iterations = 100

        for _ in 0..<iterations {
            _ = try await service.lookup("beutiful")
        }

        let elapsed = Date().timeIntervalSince(started) / Double(iterations)
        XCTAssertLessThan(elapsed, 0.100, "Average close match took \(elapsed * 1000) ms")
    }
}
