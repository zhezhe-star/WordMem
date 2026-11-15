import Foundation
import OSLog

/// Semantic phases of the adaptive import review screen. The UI renders these
/// states only; pipeline frameworks and stage numbers never reach the screen.
enum DocumentImportReviewPhase: Equatable, Sendable {
  case capturing
  case organizing
  case preparingWords
  case reviewing
  case noWordsAvailable
  case curatorUnavailable

  var isReviewReady: Bool {
    self == .reviewing || self == .noWordsAvailable || self == .curatorUnavailable
  }
}

/// Maps internal pipeline states to the user copy defined by the import
/// design. Every string is actionable Simplified Chinese and hides the
/// document pipeline, so failures stay usable instead of technical.
enum DocumentImportStatusPresenter: Sendable {
  static let noWordsMessage = "没有可保存的单词。可以换一段内容后再整理。"
  static let curatorUnavailableMessage = "暂时无法整理候选词，可以换一段内容后再试。"
  static let saveFailureMessage = "批量导入失败，请重试。"

  static func reviewStatus(for phase: DocumentImportReviewPhase) -> String? {
    switch phase {
    case .capturing:
      nil
    case .organizing:
      "正在整理内容…"
    case .preparingWords:
      "正在准备单词…"
    case .reviewing:
      nil
    case .noWordsAvailable:
      noWordsMessage
    case .curatorUnavailable:
      curatorUnavailableMessage
    }
  }

  static func translationStatus(for phase: DocumentTranslationPhase) -> String? {
    switch phase {
    case .idle:
      nil
    case .checkingAvailability, .translating:
      "正在翻译…"
    case .completed:
      nil
    case .needsLanguageDownload:
      "需要下载翻译资源后才能翻译。"
    case .unsupportedLanguagePair:
      "当前设备暂不支持这对语言的翻译。"
    case .failed(.languageDetection):
      "无法识别语言，可以直接保存单词。"
    case .failed:
      "翻译暂时不可用，可以直接保存单词。"
    }
  }

  static func processingErrorMessage(for error: Error) -> String {
    guard let imageError = error as? WordImageImportError else {
      return "暂时无法处理所选内容，请重试。"
    }
    switch imageError {
    case .invalidImageData:
      return "无法读取所选图片，请更换图片后重试。"
    case .noRecognizedText:
      return "没有识别到可整理的内容。"
    }
  }

  static func primaryButtonTitle(selectedCount: Int, isSaving: Bool) -> String {
    isSaving ? "正在导入" : "导入 \(selectedCount) 个单词"
  }
}

/// One terminal import failure. The review screen presents exactly one alert
/// and owns the retry/cancel actions; modules never render their own buttons.
struct ImportFailureAlert: Identifiable, Equatable {
  enum Kind: Equatable {
    case translation
    case imageProcessing
    case save
  }

  let id = UUID()
  let kind: Kind
  let title: String
  let message: String
  let retryTitle: String?
  let cancelTitle: String?

  var showsRetry: Bool { retryTitle != nil }
}

extension ImportFailureAlert {
  static func translation(_ report: TranslationFailureReport) -> ImportFailureAlert? {
    let documentRetryable = report.documentPhase?.isRetryableTranslationFailure == true
    let chipRetryable = report.chipPhase?.isRetryableTranslationFailure == true

    guard documentRetryable || chipRetryable else {
      return ImportFailureAlert(
        kind: .translation,
        title: "暂不支持翻译",
        message: "当前设备暂不支持英语到中文的翻译，仍可保存单词。",
        retryTitle: nil,
        cancelTitle: nil
      )
    }

    let needsDownload =
      report.documentPhase == .needsLanguageDownload
      || report.chipPhase == .needsLanguageDownload

    if needsDownload {
      return ImportFailureAlert(
        kind: .translation,
        title: "需要翻译资源",
        message: "下载语言资源后才能翻译。",
        retryTitle: "重试",
        cancelTitle: "取消导入"
      )
    }

    if documentRetryable {
      return ImportFailureAlert(
        kind: .translation,
        title: "翻译暂时不可用",
        message: "请重试；也可以取消本次导入。",
        retryTitle: "重试",
        cancelTitle: "取消导入"
      )
    }

    return ImportFailureAlert(
      kind: .translation,
      title: "部分单词释义暂不可用",
      message: "原文已翻译，请重试补齐释义。",
      retryTitle: "重试",
      cancelTitle: "取消导入"
    )
  }

  static func imageProcessing(message: String) -> ImportFailureAlert {
    ImportFailureAlert(
      kind: .imageProcessing,
      title: "无法处理这张图片",
      message: message,
      retryTitle: "重新选择",
      cancelTitle: "取消"
    )
  }

  static func saveFailure() -> ImportFailureAlert {
    ImportFailureAlert(
      kind: .save,
      title: "导入失败",
      message: "单词还没有写入，请重试。",
      retryTitle: "重试",
      cancelTitle: "取消"
    )
  }
}

/// View model behind the adaptive import review screen. It coordinates the
/// canonical document, candidate chips, and document translation while the
/// interface shows only semantic states.
@MainActor
@Observable
final class DocumentImportReviewModel {
  private(set) var phase: DocumentImportReviewPhase = .capturing
  private(set) var chips: [ImportCandidateChip] = []
  private(set) var selection = ImportChipSelection(chips: [])
  private(set) var documentSession: ImportDocumentSession?
  private(set) var preparedDisplayText = ""
  private(set) var reviewDocument: CanonicalDocument?
  private(set) var originalImageDocument: CanonicalDocument?
  private(set) var errorMessage: String?
  private(set) var isSaving = false
  private(set) var didUseDeterministicFallback = false

  /// The single alert surface for every terminal import failure.
  var failureAlert: ImportFailureAlert?

  /// Replaceable for tests so document translation stays hermetic.
  var documentSessionFactory: (CanonicalDocument) -> ImportDocumentSession = {
    ImportDocumentSession(document: $0)
  }

  private let advisor: ImportWordAdvisor
  private let curator: any ImportCandidateCurating
  private let logger = Logger(
    subsystem: "com.zhezhe.wordmem",
    category: "ImportCandidateCurator"
  )
  private var preparationToken = UUID()

  init(
    advisor: ImportWordAdvisor = .live(),
    curator: any ImportCandidateCurating = FoundationModelsCandidateCurator()
  ) {
    self.advisor = advisor
    self.curator = curator
  }

  var offeredChips: [ImportCandidateChip] {
    ImportCandidateChip.uniquelyIdentified(chips).filter(\.isOffered)
  }

  var chipTranslations: [String: String] {
    documentSession?.chipTranslations ?? [:]
  }

  var chipTranslationPhase: DocumentTranslationPhase {
    documentSession?.chipPhase ?? .idle
  }

  var isChipTranslating: Bool {
    chipTranslationPhase == .translating || chipTranslationPhase == .checkingAvailability
  }

  var selectedWords: [String] {
    selection.selectedChips.map(\.text)
  }

  var canSubmit: Bool {
    !selectedWords.isEmpty && !isSaving
  }

  var isBusy: Bool {
    phase == .organizing || phase == .preparingWords
  }

  /// The editor gives up keyboard focus once content is ready for review, so
  /// the keyboard never dominates selection.
  var shouldReleaseFocus: Bool {
    phase.isReviewReady
  }

  /// Single inline status area: errors win, then the semantic review state.
  var reviewStatusMessage: String? {
    errorMessage ?? DocumentImportStatusPresenter.reviewStatus(for: phase)
  }

  var hasDocumentTranslationCard: Bool {
    documentSession != nil
  }

  /// Deterministic review formatting used by the read-only source card.
  var reviewDisplayText: String {
    guard let reviewDocument else { return preparedDisplayText }
    return CanonicalReviewProjection.formattedText(for: reviewDocument)
  }

  /// Joined document translation, reused as phrase metadata on save.
  var translatedText: String? {
    let blocks = documentSession?.translatedDocument?.blocks ?? []
    guard !blocks.isEmpty else { return nil }
    return blocks.map(\.text).joined(separator: "\n")
  }

  // MARK: Preparation

  func reset() {
    preparationToken = UUID()
    clearResults()
    errorMessage = nil
    phase = .capturing
  }

  /// Returns typed input to capture without discarding the user's draft.
  /// Derived review state is discarded so a later commit starts from one truth.
  func beginEditingOriginal() {
    clearResults()
    errorMessage = nil
    phase = .capturing
  }

  func prepareText(_ rawText: String) async {
    let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      reset()
      return
    }

    startPreparation()
    let document = TextDocumentCanonicalizer().canonicalize(rawText, origin: .typedText)
    await prepare(from: document, displayText: rawText)
  }

  func beginImageProcessing() {
    startPreparation()
  }

  func prepareImageDocument(
    _ document: CanonicalDocument,
    displayText: String,
    originalDocument: CanonicalDocument? = nil
  ) async {
    let preparationToken = self.preparationToken
    await prepare(from: document, displayText: displayText)
    guard preparationToken == self.preparationToken else { return }
    originalImageDocument = originalDocument
  }

  func failProcessing(with error: Error) {
    clearResults()
    phase = .capturing
    errorMessage = DocumentImportStatusPresenter.processingErrorMessage(for: error)
    failureAlert = .imageProcessing(
      message: errorMessage ?? DocumentImportStatusPresenter.processingErrorMessage(for: error)
    )
  }

  /// Image imports return to the selected-image preview while keeping the
  /// recognized source so the user can pick the image again.
  func cancelTranslationKeepingSource() {
    preparationToken = UUID()
    clearResults(keepingSource: true)
    errorMessage = nil
    phase = .capturing
  }

  private func startPreparation() {
    preparationToken = UUID()
    clearResults()
    errorMessage = nil
    phase = .organizing
  }

  private func clearResults(keepingSource: Bool = false) {
    chips = []
    selection = ImportChipSelection(chips: [])
    documentSession = nil
    failureAlert = nil
    didUseDeterministicFallback = false
    if !keepingSource {
      preparedDisplayText = ""
      reviewDocument = nil
      originalImageDocument = nil
    }
  }

  private func prepare(from document: CanonicalDocument, displayText: String) async {
    let token = preparationToken

    // Document translation is optional enrichment and never blocks selection.
    // Availability is checked only after the deterministic/extended candidate
    // path has produced chips, so a slow or unavailable translation framework
    // cannot stall word preparation.
    let session = documentSessionFactory(document)
    documentSession = session
    session.onFailureReport = { [weak self] report in
      self?.presentFailureAlert(report)
    }

    phase = .preparingWords
    preparedDisplayText = displayText
    reviewDocument = document
    let deterministicCandidates = EnglishWordCandidateSplitter.candidates(from: displayText)
    // The deterministic filter is the baseline capability. Foundation Models
    // may only narrow this set; it can never introduce function words or
    // fragments that the original import flow would have excluded.
    let baseCandidates = ImportHighValueCandidateFilter.highValueCandidates(
      from: deterministicCandidates
    )
    let context = ImportCandidateCurationContext(
      sourceText: displayText,
      candidateIDs: baseCandidates.map(\.normalizedKey)
    )
    let curation = await curator.assess(
      candidates: baseCandidates,
      context: context
    )
    guard preparationToken == token else { return }

    let candidates: [WordImportCandidate]
    switch curation {
    case .curated(let assessments):
      let recommendedIDs = Set(
        assessments.filter(\.isRecommended).map(\.candidateID)
      )
      candidates = baseCandidates.filter {
        recommendedIDs.contains($0.normalizedKey)
      }
    case .failed:
      // Foundation Models is an optional enhancement. When it is unavailable,
      // times out, or errors, keep the original deterministic vocabulary set
      // instead of blocking the import flow.
      candidates = baseCandidates
      didUseDeterministicFallback = true
      logger.log(
        """
        fallback deterministic candidateCount=\(candidates.count, privacy: .public) \
        tokenCount=\(deterministicCandidates.count, privacy: .public)
        """
      )
    }

    let advisedChips = await advisor.chips(from: candidates, context: displayText)
    guard preparationToken == token else { return }

    chips = advisedChips
    selection = ImportChipSelection(chips: advisedChips)
    phase = offeredChips.isEmpty ? .noWordsAvailable : .reviewing
    session.registerChips(
      offeredChips.map { ChipTranslationUnit(id: $0.id, text: $0.text) }
    )

    // Start the visible task after the structured source and chips reach their
    // stable layout; an earlier start can be cancelled by that layout change.
    await beginDocumentTranslationIfAvailable(session)
    guard preparationToken == token else { return }
  }

  // MARK: Selection

  private func beginDocumentTranslationIfAvailable(_ session: ImportDocumentSession) async {
    let token = preparationToken
    await session.checkAvailability()
    guard preparationToken == token else { return }
    switch session.phase {
    case .translating, .needsLanguageDownload:
      session.beginTranslation()
    default:
      break
    }
  }

  func toggleSelection(_ chip: ImportCandidateChip) {
    selection.toggle(chip.id)
  }

  func selectAllWords() {
    selection.selectAll()
  }

  func clearSelection() {
    selection.clear()
  }

  func replaceSelection(_ newValue: ImportChipSelection) {
    selection = newValue
  }

  func restoreOriginal(_ chip: ImportCandidateChip) {
    let restored = chip.restoringOriginal()
    chips = chips.map { $0.id == chip.id ? restored : $0 }
    selection.updateChips(chips)
    documentSession?.moveChipTranslation(from: chip.id, to: restored.id)
  }

  // MARK: Saving

  func beginSaving() {
    isSaving = true
    errorMessage = nil
    failureAlert = nil
  }

  func endSaving() {
    isSaving = false
  }

  func failSaving() {
    isSaving = false
    errorMessage = DocumentImportStatusPresenter.saveFailureMessage
    failureAlert = .saveFailure()
  }

  // MARK: Failure alert

  func dismissFailureAlert() {
    failureAlert = nil
    documentSession?.acknowledgeFailureReport()
  }

  func retryTranslationFromAlert() {
    failureAlert = nil
    documentSession?.retry()
  }

  private func presentFailureAlert(_ report: TranslationFailureReport) {
    guard failureAlert == nil else { return }
    failureAlert = .translation(report)
  }
}

#if DEBUG
  extension DocumentImportReviewModel {
    /// Seeds a finished review state so previews exercise the real layout
    /// without running the live candidate pipeline.
    static func preview(
      sourceText: String,
      chips: [ImportCandidateChip],
      selectedOffsets: Set<Int>
    ) -> DocumentImportReviewModel {
      let model = DocumentImportReviewModel()
      model.chips = chips
      model.selection = ImportPreviewFixtures.selection(
        for: chips,
        selectedOffsets: selectedOffsets
      )
      model.preparedDisplayText = sourceText
      let isEmpty =
        sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && chips.isEmpty
      if isEmpty {
        model.phase = .capturing
      } else {
        model.phase = model.offeredChips.isEmpty ? .noWordsAvailable : .reviewing
      }
      return model
    }
  }
#endif
