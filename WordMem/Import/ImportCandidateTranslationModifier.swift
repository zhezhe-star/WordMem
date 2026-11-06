import SwiftUI
import Translation

/// Prepares one shared system-translation result for every imported candidate.
/// The canonical pipeline owns document translation; this legacy chip façade
/// now uses the same high-fidelity configuration and reports typed phases.
struct ImportCandidateTranslationModifier: ViewModifier {
  static let phraseIdentifier = "__wordmem.phrase__"

  let chips: [ImportCandidateChip]
  let sourceText: String?
  @Binding var configuration: TranslationSession.Configuration?
  @Binding var translations: [String: String]
  @Binding var phraseTranslation: String?
  @Binding var isTranslating: Bool
  @Binding var phase: DocumentTranslationPhase

  static func refreshedConfiguration(
    _ configuration: TranslationSession.Configuration?
  ) -> TranslationSession.Configuration {
    DocumentTranslationSessionFactory.refreshedHighFidelity(
      configuration,
      source: Locale.Language(identifier: "en"),
      target: Locale.Language(identifier: "zh-Hans")
    )
  }

  func body(content: Content) -> some View {
    content
      .translationTask(configuration) { session in
        await translateChips(with: session)
      }
  }

  private func translateChips(with session: TranslationSession) async {
    let pendingChips = chips.filter { translations[$0.id]?.isEmpty != false }
    let trimmedSource = sourceText?.trimmingCharacters(in: .whitespacesAndNewlines)
    let needsPhrase =
      trimmedSource?.isEmpty == false
      && phraseTranslation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false

    guard !pendingChips.isEmpty || needsPhrase else {
      isTranslating = false
      phase = .completed
      configuration = nil
      return
    }

    isTranslating = true
    phase = .translating
    var requests = pendingChips.map { chip in
      TranslationSession.Request(
        sourceText: chip.text,
        clientIdentifier: chip.id
      )
    }
    if needsPhrase, let trimmedSource {
      requests.append(
        TranslationSession.Request(
          sourceText: trimmedSource,
          clientIdentifier: Self.phraseIdentifier
        )
      )
    }

    do {
      for try await response in session.translate(batch: requests) {
        guard let identifier = response.clientIdentifier,
          !identifier.isEmpty,
          !response.targetText.isEmpty
        else {
          throw DocumentTranslationServiceError.missingResponse(
            clientIdentifier: response.clientIdentifier ?? "unknown"
          )
        }
        if identifier == Self.phraseIdentifier {
          phraseTranslation = response.targetText
        } else {
          translations[identifier] = response.targetText
        }
      }
      phase = .completed
    } catch {
      guard !Task.isCancelled else { return }
      phase = DocumentTranslationStateMapper.phase(for: error)
    }

    isTranslating = false
    configuration = nil
  }
}

extension View {
  func importCandidateTranslations(
    chips: [ImportCandidateChip],
    sourceText: String?,
    configuration: Binding<TranslationSession.Configuration?>,
    translations: Binding<[String: String]>,
    phraseTranslation: Binding<String?>,
    isTranslating: Binding<Bool>,
    phase: Binding<DocumentTranslationPhase>
  ) -> some View {
    modifier(
      ImportCandidateTranslationModifier(
        chips: chips,
        sourceText: sourceText,
        configuration: configuration,
        translations: translations,
        phraseTranslation: phraseTranslation,
        isTranslating: isTranslating,
        phase: phase
      )
    )
  }
}
