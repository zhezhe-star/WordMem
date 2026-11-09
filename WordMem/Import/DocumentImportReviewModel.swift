import Foundation
import Translation

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
  static let noWordsMessage = "没有可保存的单词。可以更换内容或手动添加。"
  static let curatorUnavailableMessage = "暂时无法整理候选词，可以更换内容或手动添加。"
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

  /// Chip-meaning façade state. The review screen binds these to the shared
  /// chip translation modifier; document translation lives in the session.
  var chipTranslationConfiguration: TranslationSession.Configuration?
  var chipTranslations: [String: String] = [:]
  var isChipTranslating = false
  var chipTranslationPhase = DocumentTranslationPhase.idle

  /// Replaceable for tests so document translation stays hermetic.
  var documentSessionFactory: (CanonicalDocument) -> ImportDocumentSession = {
    ImportDocumentSession(document: $0)
  }

  private let advisor: ImportWordAdvisor
  private let curator: any ImportCandidateCurating
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
  }

  private func startPreparation() {
    preparationToken = UUID()
    clearResults()
    errorMessage = nil
    phase = .organizing
  }

  private func clearResults() {
    chips = []
    selection = ImportChipSelection(chips: [])
    chipTranslations = [:]
    chipTranslationConfiguration = nil
    isChipTranslating = false
    chipTranslationPhase = .idle
    documentSession = nil
    preparedDisplayText = ""
    reviewDocument = nil
    originalImageDocument = nil
  }

  private func prepare(from document: CanonicalDocument, displayText: String) async {
    let token = preparationToken

    // Document translation is optional enrichment and never blocks selection.
    let session = documentSessionFactory(document)
    documentSession = session
    await session.prepare()

    guard preparationToken == token else { return }

    phase = .preparingWords
    preparedDisplayText = displayText
    reviewDocument = document
    let deterministicCandidates = EnglishWordCandidateSplitter.candidates(from: displayText)
    let context = ImportCandidateCurationContext(
      sourceText: displayText,
      candidateIDs: deterministicCandidates.map(\.normalizedKey)
    )
    let curation = await curator.assess(
      candidates: deterministicCandidates,
      context: context
    )
    guard preparationToken == token else { return }

    guard case .curated(let assessments) = curation else {
      phase = .curatorUnavailable
      return
    }

    let recommendedIDs = Set(
      assessments.filter(\.isRecommended).map(\.candidateID)
    )
    let candidates = deterministicCandidates.filter {
      recommendedIDs.contains($0.normalizedKey)
    }
    let advisedChips = await advisor.chips(from: candidates, context: displayText)
    guard preparationToken == token else { return }

    chips = advisedChips
    selection = ImportChipSelection(chips: advisedChips)
    phase = offeredChips.isEmpty ? .noWordsAvailable : .reviewing

    if !offeredChips.isEmpty {
      chipTranslationConfiguration =
        ImportCandidateTranslationModifier.refreshedConfiguration(chipTranslationConfiguration)
    }
  }

  // MARK: Selection

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
    if let translation = chipTranslations[chip.id] {
      chipTranslations[restored.id] = translation
    }
  }

  // MARK: Saving

  func beginSaving() {
    isSaving = true
    errorMessage = nil
  }

  func endSaving() {
    isSaving = false
  }

  func failSaving() {
    isSaving = false
    errorMessage = DocumentImportStatusPresenter.saveFailureMessage
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
      model.phase = model.offeredChips.isEmpty ? .noWordsAvailable : .reviewing
      return model
    }
  }
#endif
