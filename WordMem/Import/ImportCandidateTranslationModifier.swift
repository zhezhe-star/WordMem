import SwiftUI
import Translation

/// Prepares one shared system-translation result for every imported candidate.
struct ImportCandidateTranslationModifier: ViewModifier {
    let chips: [ImportCandidateChip]
    @Binding var configuration: TranslationSession.Configuration?
    @Binding var translations: [String: String]
    @Binding var isTranslating: Bool

    static func refreshedConfiguration(
        _ configuration: TranslationSession.Configuration?
    ) -> TranslationSession.Configuration {
        var next = configuration ?? TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "zh-Hans")
        )
        next.invalidate()
        return next
    }

    func body(content: Content) -> some View {
        content
            .translationTask(configuration) { session in
                await translateChips(with: session)
            }
    }

    private func translateChips(with session: TranslationSession) async {
        let pendingChips = chips.filter { translations[$0.id]?.isEmpty != false }
        guard !pendingChips.isEmpty else {
            isTranslating = false
            configuration = nil
            return
        }

        isTranslating = true
        let requests = pendingChips.map { chip in
            TranslationSession.Request(
                sourceText: chip.text,
                clientIdentifier: chip.id
            )
        }

        do {
            for try await response in session.translate(batch: requests) {
                guard let identifier = response.clientIdentifier,
                      !identifier.isEmpty,
                      !response.targetText.isEmpty
                else { continue }
                translations[identifier] = response.targetText
            }
        } catch {
            // A failed optional enrichment must not block dictionary-backed import.
        }

        isTranslating = false
        configuration = nil
    }
}

extension View {
    func importCandidateTranslations(
        chips: [ImportCandidateChip],
        configuration: Binding<TranslationSession.Configuration?>,
        translations: Binding<[String: String]>,
        isTranslating: Binding<Bool>
    ) -> some View {
        modifier(
            ImportCandidateTranslationModifier(
                chips: chips,
                configuration: configuration,
                translations: translations,
                isTranslating: isTranslating
            )
        )
    }
}
