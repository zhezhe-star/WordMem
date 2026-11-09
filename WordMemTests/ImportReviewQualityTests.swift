import CoreGraphics
import Foundation
import Translation
import XCTest

@testable import WordMem

@MainActor
final class ImportReviewQualityTests: XCTestCase {
  // MARK: - Text structured projection

  func testTextProjectionRendersCanonicalStructureWithoutClaimingStorageFormat() {
    let document = makeTextDocument([
      makeTextBlock("Reading Workflow", kind: .title),
      makeTextBlock("Methods", kind: .heading),
      makeTextBlock("Read the study before class.", kind: .paragraph),
      makeTextBlock("case summary", kind: .listItem),
      makeTextBlock("chapter notes", kind: .listItem),
      makeTextBlock("Read actively.", kind: .quote),
      makeTextBlock("let value = 1", kind: .code),
    ])

    let formatted = CanonicalReviewProjection.formattedText(for: document)

    XCTAssertEqual(
      formatted,
      """
      # Reading Workflow

      ## Methods

      Read the study before class.

      - case summary
      - chapter notes

      > Read actively.

      ```
      let value = 1
      ```
      """
    )
  }

  func testTextProjectionRendersTableRowsWithoutDuplicatingCells() {
    let document = makeTextDocument([
      makeTextBlock("Metric\tChange\nRevenue\t18%", kind: .table),
      makeTextBlock("Metric", kind: .tableCell),
      makeTextBlock("Change", kind: .tableCell),
      makeTextBlock("Revenue", kind: .tableCell),
      makeTextBlock("18%", kind: .tableCell),
    ])

    let formatted = CanonicalReviewProjection.formattedText(for: document)

    XCTAssertEqual(formatted, "| Metric | Change |\n| Revenue | 18% |")
    XCTAssertEqual(formatted.components(separatedBy: "Revenue").count - 1, 1)
  }

  func testEditingOriginalClearsDerivedReviewAndReturnsToEditableCapture() async {
    let model = makeModel(available: ["study"])

    await model.prepareText("Study the case carefully.")
    XCTAssertEqual(model.phase, .reviewing)
    XCTAssertNotNil(model.reviewDocument)

    model.beginEditingOriginal()

    XCTAssertEqual(model.phase, .capturing)
    XCTAssertNil(model.reviewDocument)
    XCTAssertNil(model.documentSession)
    XCTAssertTrue(model.chips.isEmpty)
    XCTAssertTrue(model.preparedDisplayText.isEmpty)
  }

  // MARK: - Image review sanitization

  func testImageSanitizerRemovesScreenshotNoiseAndPreservesCanonicalEvidence() {
    let original = makeNoisyImageDocument()
    let review = ImageReviewDocumentSanitizer.reviewDocument(from: original)

    let text = review.blocks.map(\.text).joined(separator: "\n")
    XCTAssertFalse(text.contains("9:41"))
    XCTAssertFalse(text.contains("100%"))
    XCTAssertFalse(text.contains("https://anthropic.com"))
    XCTAssertFalse(text.contains("Wi-Fi"))
    XCTAssertTrue(text.contains("Anthropic publishes safety research."))
    XCTAssertTrue(text.contains("Study the case carefully."))

    XCTAssertEqual(original.blocks.map(\.text), makeNoisyImageTexts())
    XCTAssertNotEqual(review.id, original.id)
    XCTAssertEqual(review.origin, original.origin)
    XCTAssertEqual(
      ImageReviewDocumentSanitizer.reviewDocument(from: original),
      review
    )
  }

  func testImageSanitizerKeepsTopTitleButRemovesShortTopChrome() {
    let title = makeBlock("Chapter 1", kind: .title, y: 0.03)
    let chrome = makeBlock("LTE", kind: .paragraph, y: 0.04)
    let paragraph = makeBlock("The study includes a case.", kind: .paragraph, y: 0.20)
    let document = makeDocument([title, chrome, paragraph])

    let review = ImageReviewDocumentSanitizer.reviewDocument(from: document)

    XCTAssertEqual(review.blocks.map(\.text), ["Chapter 1", "The study includes a case."])
  }

  // MARK: - List and table display deduplication

  func testImageProjectionDoesNotDuplicateListItemsOrTableCells() {
    let listContainer = makeBlock(
      "Ship the reader• Test the mapper",
      kind: .list,
      y: 0.30
    )
    let firstItem = makeBlock("Ship the reader", kind: .listItem, y: 0.30)
    let secondItem = makeBlock("Test the mapper", kind: .listItem, y: 0.34)
    let tableContainer = makeBlock("Metric\tChange\nRevenue\t18%", kind: .table, y: 0.45)
    let firstCell = makeBlock("Metric", kind: .tableCell, y: 0.45)
    let secondCell = makeBlock("Change", kind: .tableCell, y: 0.45)
    let thirdCell = makeBlock("Revenue", kind: .tableCell, y: 0.50)
    let fourthCell = makeBlock("18%", kind: .tableCell, y: 0.50)
    let document = makeDocument([
      listContainer, firstItem, secondItem, tableContainer, firstCell,
      secondCell, thirdCell, fourthCell,
    ])

    let formatted = CanonicalReviewProjection.formattedText(for: document)

    XCTAssertEqual(formatted.components(separatedBy: "Ship the reader").count - 1, 1)
    XCTAssertEqual(formatted.components(separatedBy: "Test the mapper").count - 1, 1)
    XCTAssertEqual(formatted.components(separatedBy: "Metric").count - 1, 1)
    XCTAssertEqual(formatted.components(separatedBy: "| Revenue | 18% |").count - 1, 1)
    XCTAssertFalse(formatted.contains("Ship the reader• Test the mapper"))
    XCTAssertTrue(formatted.contains("- Ship the reader"))
    XCTAssertTrue(formatted.contains("- Test the mapper"))
  }

  // MARK: - Candidate filtering and selection

  func testCandidateFilterRemovesFeedbackNoiseAndKeepsLearningWords() {
    let candidates = EnglishWordCandidateSplitter.candidates(
      from: "am is are com v AI anthropic try chapter case study"
    )
    let filtered = ImportHighValueCandidateFilter.highValueCandidates(from: candidates)

    XCTAssertEqual(
      filtered.map(\.text),
      ["anthropic", "try", "chapter", "case", "study"]
    )
    XCTAssertFalse(ImportHighValueCandidateFilter.isHighValue("com"))
    XCTAssertFalse(ImportHighValueCandidateFilter.isHighValue("v"))
    XCTAssertFalse(ImportHighValueCandidateFilter.isHighValue("AI"))
    XCTAssertTrue(ImportHighValueCandidateFilter.isHighValue("anthropic"))
    XCTAssertTrue(ImportHighValueCandidateFilter.isHighValue("try"))
    XCTAssertTrue(ImportHighValueCandidateFilter.isHighValue("chapter"))
    XCTAssertTrue(ImportHighValueCandidateFilter.isHighValue("case"))
    XCTAssertTrue(ImportHighValueCandidateFilter.isHighValue("study"))
  }

  func testFilteredFunctionWordsNeverBecomeSelectableChips() async {
    let model = makeModel(available: ["study", "case", "chapter"])

    await model.prepareText("I am the study. It is a case in this chapter.")

    let offeredTexts = model.offeredChips.map(\.text)
    XCTAssertEqual(offeredTexts, ["study", "case", "chapter"])
    model.selectAllWords()
    XCTAssertEqual(Set(model.selectedWords), ["study", "case", "chapter"])
    for token in ["I", "am", "the", "It", "is", "a", "in", "this"] {
      XCTAssertFalse(
        model.offeredChips.contains { $0.text.caseInsensitiveCompare(token) == .orderedSame })
    }
  }

  func testFunctionWordOnlyInputCannotProduceChipsOrChipTranslation() async {
    let model = makeModel(available: [])

    await model.prepareText("I am. It is. www com AI v")

    XCTAssertEqual(model.phase, .noWordsAvailable)
    XCTAssertTrue(model.chips.isEmpty)
    XCTAssertTrue(model.offeredChips.isEmpty)
    XCTAssertTrue(model.chipTranslations.isEmpty)
    XCTAssertNil(model.chipTranslationConfiguration)
  }

  func testImageReviewUsesSanitizedDocumentWhileKeepingOriginalEvidence() async {
    let original = makeNoisyImageDocument()
    let review = ImageReviewDocumentSanitizer.reviewDocument(from: original)
    let model = makeModel(available: ["study"])

    await model.prepareImageDocument(
      review,
      displayText: CanonicalReviewProjection.formattedText(for: review),
      originalDocument: original
    )

    XCTAssertEqual(model.documentSession?.document, review)
    XCTAssertEqual(model.originalImageDocument, original)
    XCTAssertEqual(model.reviewDocument, review)
    XCTAssertFalse(model.preparedDisplayText.contains("9:41"))
    XCTAssertTrue(model.preparedDisplayText.contains("Study the case carefully."))
  }

  func testRapidImagePreparationKeepsOnlyLatestOriginalEvidence() async {
    let staleOriginal = makeDocument([makeBlock("Stale study", kind: .paragraph, y: 0.3)])
    let latestOriginal = makeDocument([makeBlock("Latest study", kind: .paragraph, y: 0.3)])
    let model = makeModel(available: ["study"])

    let staleTask = Task { await model.prepareText("Stale study") }
    await staleTask.value
    await model.prepareImageDocument(
      latestOriginal,
      displayText: "Latest study",
      originalDocument: latestOriginal
    )

    XCTAssertEqual(model.originalImageDocument, latestOriginal)
    XCTAssertEqual(model.preparedDisplayText, "Latest study")
  }

  // MARK: - Save compatibility

  func testSaveSubmissionPayloadCompatibilityIsUnchanged() throws {
    let advice = ImportWordAdvice(
      originalText: "studying",
      originalKey: "studying",
      context: "Keep studying the case.",
      lemma: "study",
      spellingCorrection: nil,
      finalText: "study",
      finalKey: "study",
      isDictionaryAvailable: true,
      isOriginalDictionaryAvailable: true
    )
    let chip = ImportCandidateChip(
      id: "study",
      text: "study",
      sourceOrder: 3,
      advice: advice
    )

    let payload = ImportCandidatePipeline.payload(from: chip)
    XCTAssertEqual(payload.text, "study")
    XCTAssertEqual(payload.normalizedKey, "study")
    XCTAssertEqual(payload.translation, nil)
    XCTAssertEqual(payload.metadata["sourceOrder"], "3")
    XCTAssertEqual(payload.metadata["originalWord"], "studying")
    XCTAssertEqual(payload.metadata["originalKey"], "studying")
    XCTAssertEqual(payload.metadata["lemma"], "study")
  }

  // MARK: - Fixtures

  private func makeTextDocument(_ blocks: [CanonicalBlock]) -> CanonicalDocument {
    CanonicalDocument(
      id: DeterministicReviewIdentifier.uuid(seed: blocks.map(\.text).joined(separator: "\n")),
      origin: .typedText,
      detectedLanguage: nil,
      blocks: blocks.enumerated().map { order, block in
        CanonicalBlock(
          id: block.id,
          order: order,
          kind: block.kind,
          text: block.text,
          spans: block.spans,
          geometry: block.geometry,
          confidence: block.confidence
        )
      }
    )
  }

  private func makeTextBlock(_ text: String, kind: CanonicalBlockKind) -> CanonicalBlock {
    CanonicalBlock(
      id: DeterministicReviewIdentifier.uuid(seed: "text\n\(kind.rawValue)\n\(text)"),
      order: 0,
      kind: kind,
      text: text,
      spans: [],
      geometry: nil,
      confidence: 1
    )
  }

  private func makeModel(available: Set<String>) -> DocumentImportReviewModel {
    let model = DocumentImportReviewModel(
      advisor: ImportWordAdvisor(
        lemmaProvider: QualityNoopLemmaProvider(),
        spellingSuggester: QualityNoopSpellingSuggester(),
        availability: StubQualityDictionary(available: available)
      )
    )
    model.documentSessionFactory = { document in
      ImportDocumentSession(
        document: document,
        engine: DocumentTranslationEngine(
          availabilityChecker: InstalledQualityAvailabilityChecker(),
          languageDetector: EnglishQualityLanguageDetector()
        )
      )
    }
    return model
  }

  private func makeNoisyImageDocument() -> CanonicalDocument {
    let blocks = [
      makeBlock("9:41", kind: .paragraph, y: 0.01),
      makeBlock("100%", kind: .paragraph, y: 0.02),
      makeBlock("Wi-Fi", kind: .paragraph, y: 0.03),
      makeBlock("https://anthropic.com", kind: .paragraph, y: 0.05),
      makeBlock("Anthropic publishes safety research.", kind: .paragraph, y: 0.18),
      makeBlock("Study the case carefully.", kind: .paragraph, y: 0.24),
    ]
    return makeDocument(blocks)
  }

  private func makeNoisyImageTexts() -> [String] {
    [
      "9:41", "100%", "Wi-Fi", "https://anthropic.com",
      "Anthropic publishes safety research.", "Study the case carefully.",
    ]
  }

  private func makeDocument(_ blocks: [CanonicalBlock]) -> CanonicalDocument {
    let orderedBlocks = blocks.enumerated().map { order, block in
      CanonicalBlock(
        id: block.id,
        order: order,
        kind: block.kind,
        text: block.text,
        spans: block.spans,
        geometry: block.geometry,
        confidence: block.confidence
      )
    }

    return CanonicalDocument(
      id: DeterministicReviewIdentifier.uuid(
        seed: orderedBlocks.map(\.text).joined(separator: "\n")
      ),
      origin: .image,
      detectedLanguage: nil,
      blocks: orderedBlocks
    )
  }

  private func makeBlock(
    _ text: String,
    kind: CanonicalBlockKind,
    y: CGFloat
  ) -> CanonicalBlock {
    CanonicalBlock(
      id: DeterministicReviewIdentifier.uuid(seed: "\(kind.rawValue)\n\(text)\n\(y)"),
      order: 0,
      kind: kind,
      text: text,
      spans: [],
      geometry: CanonicalGeometry(
        normalizedBoundingBox: CGRect(x: 0.1, y: y, width: 0.6, height: 0.03),
        readingOrderHint: nil,
        alignment: nil
      ),
      confidence: 0.95
    )
  }
}

private struct StubQualityDictionary: SystemDictionaryAuthorizing {
  let available: Set<String>

  func hasDefinition(forTerm term: String) async -> Bool {
    available.contains(term)
  }
}

private struct QualityNoopLemmaProvider: ImportWordLemmaProviding {
  func lemma(for word: String, context: String?) async -> String? {
    nil
  }
}

private struct QualityNoopSpellingSuggester: ImportWordSpellingSuggesting {
  func correction(for word: String) async -> String? {
    nil
  }
}

private struct InstalledQualityAvailabilityChecker: DocumentLanguageAvailabilityChecking {
  func status(
    from source: Locale.Language,
    to target: Locale.Language
  ) async throws -> DocumentLanguageAvailabilityStatus {
    .installed
  }
}

private struct EnglishQualityLanguageDetector: DocumentLanguageDetecting {
  func detectLanguage(in text: String) -> Locale.Language? {
    Locale.Language(identifier: "en")
  }
}
