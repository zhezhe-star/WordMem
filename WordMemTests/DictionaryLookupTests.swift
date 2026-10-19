import XCTest
@testable import WordMem

final class DictionaryLookupTests: XCTestCase {
    private var service: BundledDictionaryLookupService!

    override func setUp() {
        super.setUp()
        service = BundledDictionaryLookupService(catalog: DevelopmentSeedDictionaryCatalog.entries)
    }

    func testNormalizationTrimsCasePunctuationAndCurlyApostrophes() {
        XCTAssertEqual(WordInputNormalizer.normalizedKey(from: "  Beautiful! "), "beautiful")
        XCTAssertEqual(WordInputNormalizer.normalizedKey(from: "Don’t"), "don't")
    }

    func testExactLookupEnrichesWord() async throws {
        let result = try await service.lookup("beautiful")

        XCTAssertEqual(result.status, .enriched)
        XCTAssertEqual(result.entry?.headword, "beautiful")
        XCTAssertEqual(result.entry?.phonetic, "/ˈbjuːtɪfl/")
        XCTAssertEqual(result.entry?.senses.first?.chinese, "美丽的")
        XCTAssertEqual(result.entry?.forms.map(\.value), ["beautifully", "beautify"])
        XCTAssertEqual(result.entry?.tags, ["CET4", "CET6", "考研"])
    }

    func testInflectedInputResolvesToLemmaWhilePreservingInput() async throws {
        let result = try await service.lookup("gave")

        XCTAssertEqual(result.status, .lemmaResolved)
        XCTAssertEqual(result.entry?.headword, "give")
        XCTAssertEqual(result.originalInput, "gave")
    }

    func testCloseInputReturnsHighConfidenceCorrection() async throws {
        let result = try await service.lookup("beutiful")

        XCTAssertEqual(result.status, .autoCorrected)
        XCTAssertEqual(result.entry?.headword, "beautiful")
    }

    func testUnknownInputReturnsNotFoundWithBareEntry() async throws {
        let result = try await service.lookup("zheeple")

        XCTAssertEqual(result.status, .notFound)
        XCTAssertEqual(result.entry?.headword, "zheeple")
        XCTAssertTrue(result.entry?.senses.isEmpty ?? false)
    }
}
