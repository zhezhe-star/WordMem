import Foundation
import SwiftUI
import Translation
import UIKit
import XCTest

@testable import WordMem

@MainActor
final class DocumentImportReviewModelTests: XCTestCase {
  // MARK: - Text preparation

  func testEmptyPreviewStartsInCapturingState() {
    let model = DocumentImportReviewModel.preview(
      sourceText: "",
      chips: [],
      selectedOffsets: []
    )

    XCTAssertEqual(model.phase, .capturing)
    XCTAssertNil(model.reviewStatusMessage)
  }

  func testPrepareTextReachesReviewingWithOfferedChips() async {
    let model = makeModel(available: ["garden"], curatedIDs: ["garden"])

    await model.prepareText("The garden grows quickly.")

    XCTAssertEqual(model.phase, .reviewing)
    XCTAssertEqual(model.offeredChips.map(\.text), ["garden"])
    XCTAssertTrue(model.offeredChips.allSatisfy(\.isImportable))
    XCTAssertTrue(model.selection.selectedChips.isEmpty)
    XCTAssertNotNil(model.documentSession)
    XCTAssertEqual(model.preparedDisplayText, "The garden grows quickly.")
  }

  func testPreparationRunsThroughOrganizingStateBeforeCandidates() async {
    let model = makeModel(available: ["garden"], curatedIDs: ["garden", "grows"])
    var phaseWhenSessionCreated: DocumentImportReviewPhase?
    model.documentSessionFactory = { document in
      phaseWhenSessionCreated = model.phase
      return ImportDocumentSession(
        document: document,
        engine: self.makeEngine(status: .installed)
      )
    }

    await model.prepareText("The garden grows quickly.")

    XCTAssertEqual(phaseWhenSessionCreated, .organizing)
    XCTAssertEqual(model.phase, .reviewing)
  }

  func testDocumentTranslationFailureKeepsWordsSelectable() async {
    let model = makeModel(
      available: ["garden"],
      curatedIDs: ["garden"],
      availabilityStatus: .unsupported
    )

    await model.prepareText("The garden grows quickly.")

    XCTAssertEqual(model.documentSession?.phase, .unsupportedLanguagePair)
    XCTAssertNil(
      model.reviewStatusMessage,
      "Translation failure must not surface as a blocking error."
    )
    XCTAssertEqual(model.offeredChips.map(\.text), ["garden"])
    XCTAssertNil(
      model.chipTranslationConfiguration,
      "Optional chip translation must not start when the pair is unsupported."
    )

    model.toggleSelection(model.offeredChips[0])

    XCTAssertEqual(model.selectedWords, ["garden"])
    XCTAssertTrue(model.canSubmit)
  }

  func testFailedTranslationCanRetryIntoTranslatingPhase() async {
    let model = makeModel(
      available: ["garden"],
      curatedIDs: ["garden"],
      availabilityStatus: .unsupported
    )
    await model.prepareText("The garden grows quickly.")
    guard let session = model.documentSession else {
      return XCTFail("Document session should exist after preparation.")
    }

    session.retry()

    XCTAssertEqual(session.phase, .translating)
  }

  func testCuratorFailureKeepsDocumentTranslationRetryable() async throws {
    let advisor = ImportWordAdvisor(
      lemmaProvider: NoopLemmaProvider(),
      spellingSuggester: NoopSpellingSuggester(),
      availability: StubAvailabilityDictionary(available: ["garden"])
    )
    let model = DocumentImportReviewModel(
      advisor: advisor,
      curator: FailingDocumentCurator()
    )
    model.documentSessionFactory = { document in
      ImportDocumentSession(
        document: document,
        engine: self.makeEngine(status: .installed)
      )
    }

    await model.prepareText("The garden grows quickly.")

    XCTAssertEqual(model.phase, .reviewing)
    XCTAssertEqual(model.offeredChips.map(\.text), ["garden"])
    let session = try XCTUnwrap(model.documentSession)
    XCTAssertEqual(session.phase, .translating)
    XCTAssertNotNil(session.configuration)
  }

  func testSimulatorFoundationModelFailureFallsBackToDeterministicChips() async {
    guard #available(iOS 26.0, *) else {
      return XCTFail("The app target requires iOS 26 or later.")
    }
    let model = DocumentImportReviewModel(
      advisor: makeAdvisor(available: ["garden"]),
      curator: FoundationModelsCandidateCurator()
    )
    model.documentSessionFactory = { document in
      ImportDocumentSession(
        document: document,
        engine: self.makeEngine(status: .installed)
      )
    }

    // The simulator reports Foundation Models as unavailable, so this exercises
    // the real production fallback path rather than a stub.
    await model.prepareText("The garden grows quickly.")

    XCTAssertEqual(model.phase, .reviewing)
    XCTAssertEqual(model.offeredChips.map(\.text), ["garden"])
  }

  func testCuratorFailureFallsBackToDeterministicFunctionWordFilter() async {
    let advisor = ImportWordAdvisor(
      lemmaProvider: NoopLemmaProvider(),
      spellingSuggester: NoopSpellingSuggester(),
      availability: StubAvailabilityDictionary(
        available: ["study", "case", "chapter", "am", "the", "this"]
      )
    )
    let model = DocumentImportReviewModel(
      advisor: advisor,
      curator: FailingDocumentCurator()
    )
    model.documentSessionFactory = { document in
      ImportDocumentSession(
        document: document,
        engine: self.makeEngine(status: .installed)
      )
    }

    await model.prepareText("I am the study. It is a case in this chapter.")

    XCTAssertEqual(model.phase, .reviewing)
    XCTAssertEqual(model.offeredChips.map(\.text), ["study", "case", "chapter"])
    XCTAssertTrue(model.didUseDeterministicFallback)
  }

  func testCuratorCannotIntroduceFunctionWordsOutsideDeterministicBaseline() async {
    let model = DocumentImportReviewModel(
      advisor: makeAdvisor(available: ["study", "am", "the"]),
      curator: OversizedRecommendationCurator(ids: ["study", "am", "the"])
    )
    model.documentSessionFactory = { document in
      ImportDocumentSession(
        document: document,
        engine: self.makeEngine(status: .installed)
      )
    }

    await model.prepareText("I am the study.")

    XCTAssertEqual(model.phase, .reviewing)
    XCTAssertEqual(model.offeredChips.map(\.text), ["study"])
  }

  func testDeterministicFilterRemovesFunctionWordsFragmentsAndShortTokens() {
    let candidates = EnglishWordCandidateSplitter.candidates(
      from: "am is are com v AI study case chapter"
    )

    let filtered = ImportHighValueCandidateFilter.highValueCandidates(from: candidates)

    XCTAssertEqual(filtered.map(\.text), ["study", "case", "chapter"])
  }

  func testDeterministicFallbackStillRequiresDictionaryAvailability() async {
    let advisor = ImportWordAdvisor(
      lemmaProvider: NoopLemmaProvider(),
      spellingSuggester: NoopSpellingSuggester(),
      availability: StubAvailabilityDictionary(available: ["study"])
    )
    let model = DocumentImportReviewModel(
      advisor: advisor,
      curator: FailingDocumentCurator()
    )
    model.documentSessionFactory = { document in
      ImportDocumentSession(
        document: document,
        engine: self.makeEngine(status: .installed)
      )
    }

    await model.prepareText("Study garden quickly.")

    XCTAssertEqual(model.phase, .reviewing)
    XCTAssertEqual(model.offeredChips.map(\.text), ["Study"])
  }

  func testTranslationAvailabilityDoesNotBlockCandidateChips() async {
    let model = DocumentImportReviewModel(
      advisor: makeAdvisor(available: ["garden"]),
      curator: StubDocumentCurator(curatedIDs: ["garden"])
    )
    model.documentSessionFactory = { document in
      ImportDocumentSession(
        document: document,
        engine: DocumentTranslationEngine(
          availabilityChecker: HangingAvailabilityChecker(),
          languageDetector: StubLanguageDetector(language: Locale.Language(identifier: "en"))
        )
      )
    }

    let preparation = Task { await model.prepareText("The garden grows quickly.") }

    for _ in 0..<200 {
      if model.phase == .reviewing { break }
      await Task.yield()
    }

    XCTAssertEqual(model.phase, .reviewing)
    XCTAssertEqual(model.offeredChips.map(\.text), ["garden"])

    preparation.cancel()
    await preparation.value
  }

  func testTranslatedTextJoinsCompletedDocumentBlocks() async {
    let model = makeModel(available: ["garden"], curatedIDs: ["garden"])
    await model.prepareText("The garden grows quickly.")
    guard let session = model.documentSession else {
      return XCTFail("Document session should exist after preparation.")
    }
    XCTAssertNil(model.translatedText)

    await session.handle(EchoDocumentTranslationSession())

    XCTAssertEqual(session.phase, .completed)
    XCTAssertEqual(model.translatedText, "译文")
  }

  func testNoOfferedWordsShowsSemanticNoWordsState() async {
    let model = makeModel(available: [], curatedIDs: [])

    await model.prepareText("Blurble zorp quux.")

    XCTAssertEqual(model.phase, .noWordsAvailable)
    XCTAssertEqual(
      model.reviewStatusMessage,
      "没有可保存的单词。可以换一段内容后再整理。"
    )
    XCTAssertTrue(model.offeredChips.isEmpty)
    XCTAssertTrue(model.shouldReleaseFocus)
    XCTAssertFalse(model.canSubmit)
  }

  func testClearingTextResetsReviewState() async {
    let model = makeModel(available: ["garden"], curatedIDs: ["garden"])
    await model.prepareText("The garden grows quickly.")

    await model.prepareText("   ")

    XCTAssertEqual(model.phase, .capturing)
    XCTAssertTrue(model.chips.isEmpty)
    XCTAssertNil(model.documentSession)
    XCTAssertNil(model.reviewStatusMessage)
    XCTAssertFalse(model.shouldReleaseFocus)
  }

  func testRapidReprocessingKeepsOnlyLatestPreparation() async {
    let dictionary = ReleasableDictionary()
    let model = DocumentImportReviewModel(
      advisor: ImportWordAdvisor(
        lemmaProvider: NoopLemmaProvider(),
        spellingSuggester: NoopSpellingSuggester(),
        availability: dictionary
      ),
      curator: AlwaysAvailableStubCurator()
    )
    model.documentSessionFactory = { document in
      ImportDocumentSession(
        document: document,
        engine: self.makeEngine(status: .installed)
      )
    }

    let staleTask = Task { await model.prepareText("garden") }
    await dictionary.waitUntilWaiting(count: 1)

    let latestTask = Task { await model.prepareText("Blurble zorp quux.") }
    await dictionary.waitUntilWaiting(count: 2)
    await dictionary.releaseAll(with: false)

    await staleTask.value
    await latestTask.value

    XCTAssertEqual(model.phase, .noWordsAvailable)
    XCTAssertTrue(model.offeredChips.isEmpty)
    XCTAssertEqual(model.chips.map(\.text), ["Blurble", "zorp", "quux"])
    XCTAssertTrue(model.selectedWords.isEmpty)
    XCTAssertFalse(model.selectedWords.contains("garden"))
  }

  // MARK: - Image preparation

  func testImageProcessingMovesFromOrganizingToReviewing() async {
    let model = makeModel(available: ["garden", "views"], curatedIDs: ["garden", "views"])

    model.beginImageProcessing()
    XCTAssertEqual(model.phase, .organizing)
    XCTAssertEqual(model.reviewStatusMessage, "正在整理内容…")
    XCTAssertTrue(model.isBusy)

    let document = TextDocumentCanonicalizer().canonicalize("Garden views", origin: .image)
    await model.prepareImageDocument(document, displayText: "Garden views")

    XCTAssertEqual(model.phase, .reviewing)
    XCTAssertFalse(model.isBusy)
    XCTAssertEqual(model.preparedDisplayText, "Garden views")
  }

  func testImageProcessingErrorsUseActionableSemanticCopy() {
    XCTAssertEqual(
      DocumentImportStatusPresenter.processingErrorMessage(
        for: WordImageImportError.invalidImageData
      ),
      "无法读取所选图片，请更换图片后重试。"
    )
    XCTAssertEqual(
      DocumentImportStatusPresenter.processingErrorMessage(
        for: WordImageImportError.noRecognizedText
      ),
      "没有识别到可整理的内容。"
    )
    XCTAssertEqual(
      DocumentImportStatusPresenter.processingErrorMessage(for: URLError(.badURL)),
      "暂时无法处理所选内容，请重试。"
    )
  }

  func testFailedImageProcessingRestoresCapturingState() async {
    let model = makeModel(available: ["garden"], curatedIDs: ["garden"])
    await model.prepareText("The garden grows quickly.")

    model.failProcessing(with: WordImageImportError.noRecognizedText)

    XCTAssertEqual(model.phase, .capturing)
    XCTAssertTrue(model.chips.isEmpty)
    XCTAssertNil(model.documentSession)
    XCTAssertEqual(
      model.reviewStatusMessage,
      "没有识别到可整理的内容。"
    )
  }

  // MARK: - Selection and saving

  func testSelectionUpdatesTrackOfferedChipsOnly() async {
    let model = makeModel(available: ["garden", "grows"], curatedIDs: ["garden", "grows"])
    await model.prepareText("The garden grows quickly.")
    let offered = model.offeredChips
    XCTAssertEqual(offered.count, 2)

    model.selectAllWords()
    XCTAssertEqual(model.selectedWords, ["garden", "grows"])
    XCTAssertTrue(model.canSubmit)

    model.clearSelection()
    XCTAssertTrue(model.selectedWords.isEmpty)
    XCTAssertFalse(model.canSubmit)
  }

  func testSavingLifecycleShowsConciseFailureAndRecovers() async {
    let model = makeModel(available: ["garden"], curatedIDs: ["garden"])
    await model.prepareText("The garden grows quickly.")

    model.beginSaving()
    XCTAssertTrue(model.isSaving)
    XCTAssertFalse(model.canSubmit, "Saving must disable resubmission.")

    model.failSaving()
    XCTAssertFalse(model.isSaving)
    XCTAssertEqual(model.reviewStatusMessage, "批量导入失败，请重试。")

    model.beginSaving()
    model.endSaving()
    XCTAssertNil(model.errorMessage)
    XCTAssertFalse(model.isSaving)
  }

  func testPrimaryButtonTitleAlwaysShowsSelectedCount() {
    XCTAssertEqual(
      DocumentImportStatusPresenter.primaryButtonTitle(selectedCount: 0, isSaving: false),
      "导入 0 个单词"
    )
    XCTAssertEqual(
      DocumentImportStatusPresenter.primaryButtonTitle(selectedCount: 2, isSaving: false),
      "导入 2 个单词"
    )
    XCTAssertEqual(
      DocumentImportStatusPresenter.primaryButtonTitle(selectedCount: 2, isSaving: true),
      "正在导入"
    )
  }

  // MARK: - Pipeline hiding

  func testTerminalStatusViewRendersMessageWithoutProgress() {
    let view = ImportInlineStatusView(
      text: DocumentImportStatusPresenter.curatorUnavailableMessage,
      isError: false,
      showsProgress: false
    )
    .frame(width: 320, height: 44)
    .background(Color.white)

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2

    guard let image = renderer.uiImage else {
      return XCTFail("Expected the terminal status to render an image.")
    }
    XCTAssertTrue(
      containsNonWhitePixels(image),
      "Terminal status copy must render even without a progress indicator."
    )
  }

  func testUserCopyHidesPipelineTerminology() {
    let userVisibleStrings = [
      DocumentImportStatusPresenter.reviewStatus(for: .organizing),
      DocumentImportStatusPresenter.reviewStatus(for: .preparingWords),
      DocumentImportStatusPresenter.reviewStatus(for: .noWordsAvailable),
      DocumentImportStatusPresenter.translationStatus(for: .checkingAvailability),
      DocumentImportStatusPresenter.translationStatus(for: .translating),
      DocumentImportStatusPresenter.translationStatus(for: .needsLanguageDownload),
      DocumentImportStatusPresenter.translationStatus(for: .unsupportedLanguagePair),
      DocumentImportStatusPresenter.translationStatus(for: .failed(.languageDetection)),
      DocumentImportStatusPresenter.translationStatus(
        for: .failed(.internalFailure("VNRecognizeTextRequest crashed"))
      ),
      DocumentImportStatusPresenter.processingErrorMessage(
        for: WordImageImportError.invalidImageData
      ),
      DocumentImportStatusPresenter.processingErrorMessage(
        for: WordImageImportError.noRecognizedText
      ),
      DocumentImportStatusPresenter.saveFailureMessage,
      DocumentImportStatusPresenter.primaryButtonTitle(selectedCount: 3, isSaving: false),
    ]

    let forbiddenTerms = [
      "Vision",
      "OCR",
      "Foundation",
      "Translation",
      "TranslationSession",
      "Recognize",
      "batch",
      "Stage",
      "Step",
      "阶段",
      "步骤",
    ]

    for userVisibleString in userVisibleStrings.compactMap({ $0 }) {
      for forbiddenTerm in forbiddenTerms {
        XCTAssertFalse(
          userVisibleString.contains(forbiddenTerm),
          "User copy '\(userVisibleString)' must not expose '\(forbiddenTerm)'."
        )
      }
    }
  }

  func testTranslationStatusesMapToDesignCopy() {
    XCTAssertEqual(
      DocumentImportStatusPresenter.translationStatus(for: .translating),
      "正在翻译…"
    )
    XCTAssertEqual(
      DocumentImportStatusPresenter.translationStatus(for: .needsLanguageDownload),
      "需要下载翻译资源后才能翻译。"
    )
    XCTAssertEqual(
      DocumentImportStatusPresenter.translationStatus(for: .unsupportedLanguagePair),
      "当前设备暂不支持这对语言的翻译。"
    )
    XCTAssertEqual(
      DocumentImportStatusPresenter.translationStatus(for: .failed(.languageDetection)),
      "无法识别语言，可以直接保存单词。"
    )
    XCTAssertEqual(
      DocumentImportStatusPresenter.translationStatus(
        for: .failed(.internalFailure("missing response"))
      ),
      "翻译暂时不可用，可以直接保存单词。"
    )
    XCTAssertNil(DocumentImportStatusPresenter.translationStatus(for: .idle))
    XCTAssertNil(DocumentImportStatusPresenter.translationStatus(for: .completed))
  }

  // MARK: - Fixtures

  private func makeModel(
    available: Set<String>,
    curatedIDs: Set<String> = [],
    availabilityStatus: DocumentLanguageAvailabilityStatus = .installed
  ) -> DocumentImportReviewModel {
    let model = DocumentImportReviewModel(
      advisor: makeAdvisor(available: available),
      curator: StubDocumentCurator(curatedIDs: curatedIDs)
    )
    model.documentSessionFactory = { document in
      ImportDocumentSession(
        document: document,
        engine: self.makeEngine(status: availabilityStatus)
      )
    }
    return model
  }

  private func makeAdvisor(available: Set<String>) -> ImportWordAdvisor {
    ImportWordAdvisor(
      lemmaProvider: NoopLemmaProvider(),
      spellingSuggester: NoopSpellingSuggester(),
      availability: StubSystemDictionary(available: available)
    )
  }

  private func makeEngine(
    status: DocumentLanguageAvailabilityStatus
  ) -> DocumentTranslationEngine {
    DocumentTranslationEngine(
      availabilityChecker: StubAvailabilityChecker(status: status),
      languageDetector: StubLanguageDetector(language: Locale.Language(identifier: "en"))
    )
  }

  private func containsNonWhitePixels(_ image: UIImage) -> Bool {
    guard let cgImage = image.cgImage else { return false }
    let width = cgImage.width
    let height = cgImage.height
    guard width > 0, height > 0 else { return false }

    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard
      let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return false }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    for index in stride(from: 0, to: pixels.count, by: 4) {
      if pixels[index] < 245 || pixels[index + 1] < 245 || pixels[index + 2] < 245 {
        return true
      }
    }
    return false
  }
}

private struct StubSystemDictionary: SystemDictionaryAuthorizing {
  let available: Set<String>

  func hasDefinition(forTerm term: String) async -> Bool {
    available.contains(term)
  }
}

private actor ReleasableDictionary: SystemDictionaryAuthorizing {
  private var continuations: [CheckedContinuation<Bool, Never>] = []
  private var isReleasing = false

  func hasDefinition(forTerm term: String) async -> Bool {
    if isReleasing {
      return false
    }

    return await withCheckedContinuation { continuation in
      continuations.append(continuation)
    }
  }

  func waitUntilWaiting(count: Int) async {
    while continuations.count < count {
      await Task.yield()
    }
  }

  func releaseAll(with value: Bool) {
    isReleasing = true
    let pending = continuations
    continuations = []
    for continuation in pending {
      continuation.resume(returning: value)
    }
  }
}

private struct NoopLemmaProvider: ImportWordLemmaProviding {
  func lemma(for word: String, context: String?) async -> String? {
    nil
  }
}

private struct NoopSpellingSuggester: ImportWordSpellingSuggesting {
  func correction(for word: String) async -> String? {
    nil
  }
}

private struct StubDocumentCurator: ImportCandidateCurating {
  let curatedIDs: Set<String>

  func assess(
    candidates: [WordImportCandidate],
    context: ImportCandidateCurationContext
  ) async -> ImportCandidateCurationResult {
    guard !context.isEmpty else { return .failed }
    let knownIDs = Set(context.candidateIDs)
    let hasCuration = !curatedIDs.isEmpty
    let assessments =
      hasCuration
      ? curatedIDs.intersection(knownIDs).map { id in
        ImportCandidateAssessment(
          candidateID: id,
          isRecommended: true,
          valueScore: 8,
          shortReason: "值得学习",
          contextualMeaning: nil
        )
      }
      : []
    if assessments.isEmpty {
      return hasCuration ? .failed : .curated([])
    }
    return .curated(assessments.sorted { $0.candidateID < $1.candidateID })
  }
}

private struct AlwaysAvailableStubCurator: ImportCandidateCurating {
  func assess(
    candidates: [WordImportCandidate],
    context: ImportCandidateCurationContext
  ) async -> ImportCandidateCurationResult {
    .curated(
      candidates.map { candidate in
        ImportCandidateAssessment(
          candidateID: candidate.normalizedKey,
          isRecommended: true,
          valueScore: 5,
          shortReason: "原文",
          contextualMeaning: nil
        )
      }
    )
  }
}

private struct StubAvailabilityChecker: DocumentLanguageAvailabilityChecking {
  let status: DocumentLanguageAvailabilityStatus

  func status(
    from source: Locale.Language,
    to target: Locale.Language
  ) async throws -> DocumentLanguageAvailabilityStatus {
    status
  }
}

private struct HangingAvailabilityChecker: DocumentLanguageAvailabilityChecking {
  func status(
    from source: Locale.Language,
    to target: Locale.Language
  ) async throws -> DocumentLanguageAvailabilityStatus {
    try await Task.sleep(for: .seconds(30))
    return .installed
  }
}

private struct StubAvailabilityDictionary: SystemDictionaryAuthorizing {
  let available: Set<String>

  func hasDefinition(forTerm term: String) async -> Bool {
    available.contains(term)
  }
}

private struct FailingDocumentCurator: ImportCandidateCurating {
  func assess(
    candidates: [WordImportCandidate],
    context: ImportCandidateCurationContext
  ) async -> ImportCandidateCurationResult {
    .failed
  }
}

private struct OversizedRecommendationCurator: ImportCandidateCurating {
  let ids: [String]

  func assess(
    candidates: [WordImportCandidate],
    context: ImportCandidateCurationContext
  ) async -> ImportCandidateCurationResult {
    .curated(
      ids.map { id in
        ImportCandidateAssessment(
          candidateID: id,
          isRecommended: true,
          valueScore: 10,
          shortReason: "测试",
          contextualMeaning: nil
        )
      }
    )
  }
}

private struct StubLanguageDetector: DocumentLanguageDetecting {
  let language: Locale.Language?

  func detectLanguage(in text: String) -> Locale.Language? {
    language
  }
}

private struct EchoDocumentTranslationSession: DocumentTranslationSessionHandling {
  func translate(
    _ requests: [DocumentTranslationRequest]
  ) async throws -> [DocumentTranslationResponse] {
    requests.map { request in
      DocumentTranslationResponse(
        clientIdentifier: request.clientIdentifier,
        targetText: "译文"
      )
    }
  }
}
