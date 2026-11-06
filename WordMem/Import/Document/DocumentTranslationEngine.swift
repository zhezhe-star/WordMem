import Foundation
import NaturalLanguage
import Translation

/// Runtime implementation used by the main app. iOS 27 lets us request
/// high-fidelity output instead of relying on the legacy default strategy.
struct SystemDocumentLanguageAvailabilityChecker: DocumentLanguageAvailabilityChecking {
  func status(
    from source: Locale.Language,
    to target: Locale.Language
  ) async throws -> DocumentLanguageAvailabilityStatus {
    let availability = LanguageAvailability(preferredStrategy: .highFidelity)
    let status = await availability.status(from: source, to: target)
    switch status {
    case .installed: return .installed
    case .supported: return .supportedNotInstalled
    case .unsupported: return .unsupported
    @unknown default:
      throw DocumentLanguageAvailabilityError.unsupportedLanguagePair
    }
  }
}

struct NaturalLanguageDocumentDetector: Sendable {
  func detectLanguage(in text: String) -> Locale.Language? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let recognizer = NLLanguageRecognizer()
    recognizer.processString(trimmed)
    guard let language = recognizer.dominantLanguage else { return nil }
    return Locale.Language(identifier: language.rawValue)
  }
}

struct SystemDocumentTranslationSession: DocumentTranslationSessionHandling {
  // SwiftUI supplies this session on the main actor; the adapter forwards it
  // without crossing actors. Translation currently does not mark the class
  // Sendable even though its request/response values are Sendable.
  private nonisolated(unsafe) let session: TranslationSession

  init(_ session: TranslationSession) {
    self.session = session
  }

  func translate(
    _ requests: [DocumentTranslationRequest]
  ) async throws -> [DocumentTranslationResponse] {
    let batchRequests = requests.map { request in
      TranslationSession.Request(
        sourceText: request.sourceText,
        clientIdentifier: request.clientIdentifier
      )
    }

    let responses = try await session.translations(from: batchRequests)
    return responses.map {
      DocumentTranslationResponse(
        clientIdentifier: $0.clientIdentifier ?? "",
        targetText: $0.targetText
      )
    }
  }
}

enum DocumentTranslationSessionFactory {
  static func highFidelity(
    source: Locale.Language?,
    target: Locale.Language
  ) -> TranslationSession.Configuration {
    TranslationSession.Configuration(
      source: source,
      target: target,
      preferredStrategy: .highFidelity
    )
  }

  static func refreshedHighFidelity(
    _ configuration: TranslationSession.Configuration?,
    source: Locale.Language,
    target: Locale.Language
  ) -> TranslationSession.Configuration {
    var next = configuration ?? highFidelity(source: source, target: target)
    next.invalidate()
    return next
  }
}

/// Stateless canonical-document translation. Availability checking is kept
/// separate so UI lifecycle transitions and every dependency are testable
/// without starting a system translation session.
struct DocumentTranslationEngine: Sendable {
  private let availabilityChecker: any DocumentLanguageAvailabilityChecking
  private let languageDetector: any DocumentLanguageDetecting

  init(
    availabilityChecker: any DocumentLanguageAvailabilityChecking =
      SystemDocumentLanguageAvailabilityChecker(),
    languageDetector: any DocumentLanguageDetecting = NaturalLanguageDocumentDetector()
  ) {
    self.availabilityChecker = availabilityChecker
    self.languageDetector = languageDetector
  }

  func sourceLanguage(
    in document: CanonicalDocument,
    preferredSource: Locale.Language? = nil
  ) throws -> Locale.Language {
    if let preferredSource { return preferredSource }
    if let detected = document.detectedLanguage { return detected }

    let text = document.blocks.map(\.text).joined(separator: "\n")
    guard let detected = languageDetector.detectLanguage(in: text) else {
      throw DocumentTranslationServiceError.languageDetectionFailed
    }
    return detected
  }

  /// Caller transitions to `.checkingAvailability` before invoking this
  /// method; this method returns the resulting terminal-or-ready phase.
  func availabilityPhase(
    for document: CanonicalDocument,
    target: Locale.Language,
    preferredSource: Locale.Language? = nil
  ) async -> DocumentTranslationPhase {
    do {
      let source = try sourceLanguage(in: document, preferredSource: preferredSource)
      let status = try await availabilityChecker.status(from: source, to: target)
      switch status {
      case .installed:
        return .translating
      case .supportedNotInstalled:
        return .needsLanguageDownload
      case .unsupported:
        return .unsupportedLanguagePair
      }
    } catch {
      return DocumentTranslationStateMapper.phase(for: error)
    }
  }

  func translate(
    document: CanonicalDocument,
    target: Locale.Language,
    using session: any DocumentTranslationSessionHandling,
    preserving userEditedTranslations: [UUID: TranslatedBlock] = [:]
  ) async throws -> TranslatedDocument {
    _ = try sourceLanguage(in: document)
    let translationUnits = document.translationUnitBlocks
    var translatedByID: [UUID: TranslatedBlock] = [:]
    translatedByID.reserveCapacity(translationUnits.count)
    var requests: [DocumentTranslationRequest] = []

    for block in translationUnits {
      if let userEdited = userEditedTranslations[block.id],
        userEdited.state == .userEdited
      {
        translatedByID[block.id] = userEdited
        continue
      }

      let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        translatedByID[block.id] = Self.failedBlock(from: block, text: block.text)
        continue
      }

      let request = DocumentTranslationRequest(
        clientIdentifier: block.id.uuidString,
        sourceBlockID: block.id,
        sourceSpanID: block.spans.first?.id,
        sourceText: trimmed
      )
      requests.append(request)
    }

    let responses: [DocumentTranslationResponse]
    let responseByID: [UUID: DocumentTranslationResponse]
    if requests.isEmpty {
      responses = []
      responseByID = [:]
    } else {
      responses = try await session.translate(requests)
      responseByID = try Self.validatedResponses(
        for: requests,
        responses: responses
      )
    }

    for block in translationUnits where translatedByID[block.id] == nil {
      let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let response = responseByID[block.id], !trimmed.isEmpty else {
        translatedByID[block.id] = Self.failedBlock(from: block, text: block.text)
        continue
      }

      translatedByID[block.id] = Self.translatedBlock(
        from: block,
        text: response.targetText
      )
    }

    let blocks = translationUnits.compactMap { translatedByID[$0.id] }
    return TranslatedDocument(
      id: UUID(),
      sourceDocumentID: document.id,
      targetLanguage: target,
      blocks: blocks
    )
  }

  private static func validatedResponses(
    for requests: [DocumentTranslationRequest],
    responses: [DocumentTranslationResponse]
  ) throws -> [UUID: DocumentTranslationResponse] {
    var responseByID: [UUID: DocumentTranslationResponse] = [:]
    responseByID.reserveCapacity(requests.count)

    for response in responses {
      guard let id = UUID(uuidString: response.clientIdentifier) else {
        throw DocumentTranslationServiceError.missingResponse(
          clientIdentifier: response.clientIdentifier
        )
      }
      guard !response.targetText.isEmpty else {
        throw DocumentTranslationServiceError.emptyTranslation(
          clientIdentifier: response.clientIdentifier
        )
      }
      responseByID[id] = response
    }

    for request in requests where responseByID[request.sourceBlockID] == nil {
      throw DocumentTranslationServiceError.missingResponse(
        clientIdentifier: request.clientIdentifier
      )
    }

    return responseByID
  }

  private static func translatedBlock(
    from block: CanonicalBlock,
    text: String
  ) -> TranslatedBlock {
    let spans = block.spans.map { span in
      TranslatedSpan(
        id: UUID(),
        sourceSpanID: span.id,
        targetCharRange: 0..<text.utf16.count,
        state: .needsReview
      )
    }

    return TranslatedBlock(
      id: UUID(),
      sourceBlockID: block.id,
      text: text,
      attributedSnapshot: nil,
      spans: spans,
      state: .systemTranslated
    )
  }

  private static func failedBlock(
    from block: CanonicalBlock,
    text: String
  ) -> TranslatedBlock {
    let spans = block.spans.map { span in
      TranslatedSpan(
        id: UUID(),
        sourceSpanID: span.id,
        targetCharRange: 0..<text.utf16.count,
        state: .failed
      )
    }

    return TranslatedBlock(
      id: UUID(),
      sourceBlockID: block.id,
      text: text,
      attributedSnapshot: nil,
      spans: spans,
      state: .failed
    )
  }
}

protocol DocumentLanguageDetecting: Sendable {
  func detectLanguage(in text: String) -> Locale.Language?
}

extension NaturalLanguageDocumentDetector: DocumentLanguageDetecting {}
