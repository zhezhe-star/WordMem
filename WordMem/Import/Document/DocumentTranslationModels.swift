import Foundation
import Translation

/// User-visible and testable lifecycle states for canonical document
/// translation. The mapping from system availability/errors lives in one
/// place: `DocumentTranslationStateMapper`.
enum DocumentTranslationPhase: Equatable, Sendable {
  case idle
  case checkingAvailability
  case needsLanguageDownload
  case unsupportedLanguagePair
  case translating
  case completed
  case failed(DocumentTranslationFailure)
}

/// The subset of translation failures that the import UI needs to describe.
/// Framework errors are normalized here so callers never erase their type.
enum DocumentTranslationFailure: Equatable, Sendable {
  case languageDetection
  case internalFailure(String)
}

/// Availability normalized across the runtime framework and unit-test fakes.
enum DocumentLanguageAvailabilityStatus: Equatable, Sendable {
  case installed
  case supportedNotInstalled
  case unsupported
}

enum DocumentLanguageAvailabilityError: Error, Equatable, Sendable {
  case languageDetectionFailed
  case unsupportedLanguagePair
}

/// Internal invariants are explicit errors, never silently dropped responses.
enum DocumentTranslationServiceError: Error, Equatable, Sendable {
  case languageDetectionFailed
  case missingResponse(clientIdentifier: String)
  case emptyTranslation(clientIdentifier: String)
  case unsupportedLanguagePair
  case notInstalled
}

protocol DocumentLanguageAvailabilityChecking: Sendable {
  func status(from source: Locale.Language, to target: Locale.Language) async throws
    -> DocumentLanguageAvailabilityStatus
}

/// One canonical block is currently one semantic translation segment. Keeping
/// the block and span identifiers in the request preserves review provenance
/// even when the system cannot retain inline formatting.
struct DocumentTranslationRequest: Identifiable, Hashable, Sendable {
  let clientIdentifier: String
  let sourceBlockID: UUID
  let sourceSpanID: UUID?
  let sourceText: String

  var id: String { clientIdentifier }
}

struct DocumentTranslationResponse: Hashable, Sendable {
  let clientIdentifier: String
  let targetText: String
}

protocol DocumentTranslationSessionHandling: Sendable {
  func translate(_ requests: [DocumentTranslationRequest]) async throws
    -> [DocumentTranslationResponse]
}

/// Stable provenance for a translated canonical document.
struct TranslatedDocument: Identifiable, Codable, Hashable, Sendable {
  let id: UUID
  let sourceDocumentID: UUID
  let targetLanguage: Locale.Language
  var blocks: [TranslatedBlock]
}

struct TranslatedBlock: Identifiable, Codable, Hashable, Sendable {
  let id: UUID
  let sourceBlockID: UUID
  let text: String
  let attributedSnapshot: Data?
  let spans: [TranslatedSpan]
  let state: DocumentTranslationBlockState
}

struct TranslatedSpan: Identifiable, Codable, Hashable, Sendable {
  let id: UUID
  let sourceSpanID: UUID
  let targetCharRange: Range<Int>
  let state: DocumentTranslationBlockState
}

enum DocumentTranslationBlockState: String, Codable, CaseIterable, Sendable {
  case systemTranslated
  case userEdited
  case failed
  case unsupported
  case needsReview
}

/// Converts typed framework failures to the explicit phase exposed by the
/// import session. All unknown errors retain a descriptive internal reason.
enum DocumentTranslationStateMapper {
  static func phase(for error: Error) -> DocumentTranslationPhase {
    switch error {
    case DocumentLanguageAvailabilityError.languageDetectionFailed,
      DocumentTranslationServiceError.languageDetectionFailed:
      return .failed(.languageDetection)
    case DocumentLanguageAvailabilityError.unsupportedLanguagePair,
      DocumentTranslationServiceError.unsupportedLanguagePair:
      return .unsupportedLanguagePair
    case DocumentTranslationServiceError.notInstalled:
      return .needsLanguageDownload
    case TranslationError.notInstalled:
      return .needsLanguageDownload
    case TranslationError.unsupportedSourceLanguage,
      TranslationError.unsupportedTargetLanguage,
      TranslationError.unsupportedLanguagePairing:
      return .unsupportedLanguagePair
    case TranslationError.unableToIdentifyLanguage:
      return .failed(.languageDetection)
    default:
      return .failed(.internalFailure(Self.internalReason(for: error)))
    }
  }

  static func internalReason(for error: Error) -> String {
    if let serviceError = error as? DocumentTranslationServiceError {
      switch serviceError {
      case .missingResponse(let identifier):
        return "missing response: \(identifier)"
      case .emptyTranslation(let identifier):
        return "empty translation: \(identifier)"
      case .languageDetectionFailed:
        return "language detection failed"
      case .unsupportedLanguagePair:
        return "unsupported language pair"
      case .notInstalled:
        return "translation language is not installed"
      }
    }

    return String(describing: error)
  }
}
