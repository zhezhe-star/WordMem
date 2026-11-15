import SwiftUI
import Translation

/// Main-app session façade for canonical document translation. It owns the
/// explicit lifecycle, the SwiftUI translation task configuration, and user
/// edits. Dictionary-backed import can continue independently of this state.
@MainActor
@Observable
final class ImportDocumentSession {
  let document: CanonicalDocument
  let targetLanguage: Locale.Language
  private(set) var phase: DocumentTranslationPhase = .idle
  private(set) var translatedDocument: TranslatedDocument?
  private(set) var usesLowLatencyTranslation = false
  private(set) var chipTranslations: [String: String] = [:]
  private(set) var chipPhase: DocumentTranslationPhase = .idle
  private(set) var failureReport: TranslationFailureReport?
  var configuration: TranslationSession.Configuration?
  var onFailureReport: (@MainActor (TranslationFailureReport) -> Void)?

  private let engine: DocumentTranslationEngine
  private let preferredSourceLanguage: Locale.Language?
  private var userEditedTranslations: [UUID: TranslatedBlock] = [:]
  private var chipUnits: [ChipTranslationUnit] = []
  private var documentWorkPending = false
  private var chipWorkPending = false
  private var isHandling = false

  init(
    document: CanonicalDocument,
    targetLanguage: Locale.Language = Locale.Language(identifier: "zh-Hans"),
    preferredSourceLanguage: Locale.Language? = nil,
    engine: DocumentTranslationEngine = DocumentTranslationEngine()
  ) {
    self.document = document
    self.targetLanguage = targetLanguage
    self.preferredSourceLanguage = preferredSourceLanguage
    self.engine = engine
  }

  func prepare() async {
    await checkAvailability()
    switch phase {
    case .translating, .needsLanguageDownload:
      beginTranslation()
    default:
      break
    }
  }

  func checkAvailability() async {
    guard phase == .idle || phase.isRecoverableFailureOrUnavailable else { return }
    phase = .checkingAvailability
    phase = await engine.availabilityPhase(
      for: document,
      target: targetLanguage,
      preferredSource: preferredSourceLanguage
    )
    if phase.isTerminalTranslationFailure {
      publishFailureReportIfNeeded()
    }
  }

  func beginTranslation() {
    if translatedDocument == nil {
      documentWorkPending = true
      phase = .translating
    }
    if hasPendingChipTranslations {
      chipWorkPending = true
      chipPhase = .translating
    }
    guard documentWorkPending || chipWorkPending else {
      configuration = nil
      return
    }
    configuration = makeConfiguration()
  }

  /// Registers candidate words that should be translated in the same session
  /// as the document. Existing successful meanings are preserved.
  func registerChips(_ units: [ChipTranslationUnit]) {
    chipUnits = units
    let validIDs = Set(units.map(\.id))
    chipTranslations = chipTranslations.filter { validIDs.contains($0.key) }
    chipPhase = units.isEmpty ? .completed : .idle
  }

  var hasPendingChipTranslations: Bool {
    chipUnits.contains { chipTranslations[$0.id]?.isEmpty != false }
  }

  var isRunning: Bool {
    phase == .checkingAvailability || phase == .translating
      || chipPhase == .checkingAvailability || chipPhase == .translating
  }

  private func makeConfiguration() -> TranslationSession.Configuration {
    let source =
      (try? engine.sourceLanguage(in: document, preferredSource: preferredSourceLanguage))
      ?? Locale.Language(identifier: "en")

    if usesLowLatencyTranslation {
      return DocumentTranslationSessionFactory.refreshedLowLatency(
        configuration,
        source: source,
        target: targetLanguage
      )
    }
    return DocumentTranslationSessionFactory.refreshedHighFidelity(
      configuration,
      source: source,
      target: targetLanguage
    )
  }

  /// Receives the session supplied by SwiftUI's `.translationTask`.
  func handle(_ systemSession: TranslationSession) async {
    await handle(SystemDocumentTranslationSession(systemSession))
  }

  /// Testable entry point that does not require Translation runtime input.
  func handle(_ session: any DocumentTranslationSessionHandling) async {
    guard configuration != nil,
      documentWorkPending || chipWorkPending,
      !isHandling
    else { return }
    isHandling = true
    defer { isHandling = false }

    do {
      try await session.prepare()
    } catch {
      guard !handleCancellation(error) else { return }
      guard !canRetryWithLowLatency(after: error) else {
        switchToLowLatency()
        return
      }
      applyPreparationFailure(error)
      return
    }

    if documentWorkPending {
      do {
        translatedDocument = try await engine.translate(
          document: document,
          target: targetLanguage,
          using: session,
          preserving: userEditedTranslations
        )
        phase = .completed
        documentWorkPending = false
      } catch {
        guard !handleCancellation(error) else { return }
        guard !canRetryWithLowLatency(after: error) else {
          switchToLowLatency()
          return
        }
        phase = DocumentTranslationStateMapper.phase(for: error)
        documentWorkPending = false
      }
    }

    if chipWorkPending {
      do {
        try await translatePendingChips(using: session)
        chipPhase = .completed
        chipWorkPending = false
      } catch {
        guard !handleCancellation(error) else { return }
        guard !canRetryWithLowLatency(after: error) else {
          switchToLowLatency()
          return
        }
        chipPhase = DocumentTranslationStateMapper.phase(for: error)
        chipWorkPending = false
      }
    }

    if !documentWorkPending && !chipWorkPending {
      configuration = nil
      publishFailureReportIfNeeded()
    }
  }

  func retry(with session: any DocumentTranslationSessionHandling) async {
    guard !isRunning else { return }
    await resumePendingWork()
    guard configuration != nil else { return }
    await handle(session)
  }

  @discardableResult
  func retry() -> Task<Void, Never> {
    guard !isRunning else { return Task {} }
    return Task { @MainActor in
      await resumePendingWork()
    }
  }

  func acknowledgeFailureReport() {
    failureReport = nil
  }

  func moveChipTranslation(from oldID: String, to newID: String) {
    guard oldID != newID,
      let translation = chipTranslations.removeValue(forKey: oldID)
    else { return }
    chipTranslations[newID] = translation
  }

  func invalidate() {
    configuration = nil
    usesLowLatencyTranslation = false
    phase = .idle
    chipPhase = .idle
    documentWorkPending = false
    chipWorkPending = false
    failureReport = nil
  }

  private func resumePendingWork() async {
    failureReport = nil
    if translatedDocument == nil {
      await checkAvailability()
    }

    switch phase {
    case .translating, .needsLanguageDownload:
      beginTranslation()
    case .completed:
      if hasPendingChipTranslations {
        chipWorkPending = true
        chipPhase = .translating
        beginTranslation()
      }
    default:
      break
    }
  }

  private func translatePendingChips(
    using session: any DocumentTranslationSessionHandling
  ) async throws {
    let pending = chipUnits.filter {
      chipTranslations[$0.id]?.isEmpty != false
    }
    guard !pending.isEmpty else { return }

    let requests = pending.map { unit in
      DocumentTranslationRequest(
        clientIdentifier: unit.id,
        sourceBlockID: UUID(),
        sourceSpanID: nil,
        sourceText: unit.text
      )
    }
    let responses = try await session.translate(requests)
    var translated: [String: String] = [:]
    translated.reserveCapacity(requests.count)

    for response in responses {
      guard !response.clientIdentifier.isEmpty,
        !response.targetText.isEmpty
      else {
        throw DocumentTranslationServiceError.missingResponse(
          clientIdentifier: response.clientIdentifier
        )
      }
      translated[response.clientIdentifier] = response.targetText
    }

    for request in requests {
      guard let targetText = translated[request.clientIdentifier] else {
        throw DocumentTranslationServiceError.missingResponse(
          clientIdentifier: request.clientIdentifier
        )
      }
      chipTranslations[request.clientIdentifier] = targetText
    }
  }

  private func handleCancellation(_ error: Error) -> Bool {
    guard error is CancellationError || Task.isCancelled else { return false }
    // SwiftUI may cancel this task while the surrounding review layout
    // changes. Invalidate once so the reattached task starts a fresh run
    // instead of leaving a permanently spinning translation card.
    if documentWorkPending { phase = .translating }
    if chipWorkPending { chipPhase = .translating }
    configuration?.invalidate()
    return true
  }

  private func canRetryWithLowLatency(after error: Error) -> Bool {
    guard !usesLowLatencyTranslation else { return false }
    guard
      case .failed = DocumentTranslationStateMapper.phase(for: error)
    else { return false }
    return true
  }

  private func switchToLowLatency() {
    usesLowLatencyTranslation = true
    if documentWorkPending { phase = .translating }
    if chipWorkPending { chipPhase = .translating }
    configuration = makeConfiguration()
  }

  private func applyPreparationFailure(_ error: Error) {
    let failure = DocumentTranslationStateMapper.phase(for: error)
    if documentWorkPending {
      phase = failure
      documentWorkPending = false
    }
    if chipWorkPending {
      chipPhase = failure
      chipWorkPending = false
    }
    configuration = nil
    publishFailureReportIfNeeded()
  }

  private func publishFailureReportIfNeeded() {
    guard !documentWorkPending, !chipWorkPending else { return }
    let documentFailure = phase.isTerminalTranslationFailure ? phase : nil
    let chipFailure = chipPhase.isTerminalTranslationFailure ? chipPhase : nil
    guard documentFailure != nil || chipFailure != nil else {
      failureReport = nil
      return
    }
    let report = TranslationFailureReport(
      documentPhase: documentFailure,
      chipPhase: chipFailure
    )
    failureReport = report
    onFailureReport?(report)
  }

  func userEditedTranslation(blockID: UUID, text: String) {
    guard let documentBlock = document.blocks.first(where: { $0.id == blockID }) else {
      return
    }

    let edited: TranslatedBlock
    if let existing = translatedDocument?.blocks.first(where: { $0.sourceBlockID == blockID }) {
      edited = TranslatedBlock(
        id: existing.id,
        sourceBlockID: blockID,
        text: text,
        attributedSnapshot: nil,
        spans: existing.spans.map {
          TranslatedSpan(
            id: $0.id,
            sourceSpanID: $0.sourceSpanID,
            targetCharRange: 0..<text.utf16.count,
            state: .userEdited
          )
        },
        state: .userEdited
      )
    } else {
      edited = TranslatedBlock(
        id: UUID(),
        sourceBlockID: blockID,
        text: text,
        attributedSnapshot: nil,
        spans: documentBlock.spans.map {
          TranslatedSpan(
            id: UUID(),
            sourceSpanID: $0.id,
            targetCharRange: 0..<text.utf16.count,
            state: .userEdited
          )
        },
        state: .userEdited
      )
    }

    userEditedTranslations[blockID] = edited
    if var updated = translatedDocument {
      if let index = updated.blocks.firstIndex(where: { $0.sourceBlockID == blockID }) {
        updated.blocks[index] = edited
      } else {
        let insertionOrder = documentBlock.order
        let index =
          updated.blocks.firstIndex { block in
            document.blocks.first { $0.id == block.sourceBlockID }?.order ?? .max > insertionOrder
          } ?? updated.blocks.endIndex
        updated.blocks.insert(edited, at: index)
      }
      translatedDocument = updated
    }
  }
}

extension DocumentTranslationPhase {
  var isRecoverableFailureOrUnavailable: Bool {
    switch self {
    case .idle, .needsLanguageDownload, .unsupportedLanguagePair, .failed:
      return true
    case .checkingAvailability, .translating, .completed:
      return false
    }
  }
}

extension View {
  func importDocumentTranslationTask(for session: ImportDocumentSession) -> some View {
    translationTask(session.configuration) { systemSession in
      await session.handle(systemSession)
    }
  }
}
