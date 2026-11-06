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
  var configuration: TranslationSession.Configuration?

  private let engine: DocumentTranslationEngine
  private let preferredSourceLanguage: Locale.Language?
  private var userEditedTranslations: [UUID: TranslatedBlock] = [:]

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
    guard phase == .idle || phase.isRecoverableFailureOrUnavailable else { return }
    phase = .checkingAvailability
    phase = await engine.availabilityPhase(
      for: document,
      target: targetLanguage,
      preferredSource: preferredSourceLanguage
    )

    if phase == .translating {
      beginTranslation()
    }
  }

  func beginTranslation() {
    phase = .translating
    configuration = DocumentTranslationSessionFactory.refreshedHighFidelity(
      configuration,
      source: (try? engine.sourceLanguage(in: document, preferredSource: preferredSourceLanguage))
        ?? Locale.Language(identifier: "en"),
      target: targetLanguage
    )
  }

  /// Receives the session supplied by SwiftUI's `.translationTask`.
  func handle(_ systemSession: TranslationSession) async {
    await handle(SystemDocumentTranslationSession(systemSession))
  }

  /// Testable entry point that does not require Translation runtime input.
  func handle(_ session: any DocumentTranslationSessionHandling) async {
    guard phase == .translating, configuration != nil else { return }

    do {
      translatedDocument = try await engine.translate(
        document: document,
        target: targetLanguage,
        using: session,
        preserving: userEditedTranslations
      )
      phase = .completed
      configuration = nil
    } catch {
      guard !Task.isCancelled else { return }
      phase = DocumentTranslationStateMapper.phase(for: error)
      configuration = nil
    }
  }

  func retry(with session: any DocumentTranslationSessionHandling) async {
    guard phase != .translating, phase != .checkingAvailability else { return }
    beginTranslation()
    await handle(session)
  }

  func retry() {
    guard phase != .translating, phase != .checkingAvailability else { return }
    beginTranslation()
  }

  func invalidate() {
    configuration = nil
    phase = .idle
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
