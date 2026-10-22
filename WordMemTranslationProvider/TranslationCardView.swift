import SwiftUI
import Translation
import TranslationUIProvider

/// Presents one complete card: source, translation, phrase, and split words.
struct TranslationCardView: View {
    let context: any TranslationUIProviderContext

    @State private var sourceText = ""
    @State private var translatedText = ""
    @State private var status: Status = .idle
    @State private var configuration: TranslationSession.Configuration?

    private let storage = LocalStorageManager()

    enum Status: Equatable {
        case idle
        case translating
        case ready
        case translationFailed
    }

    var body: some View {
        Group {
            if sourceText.isEmpty {
                startupState
            } else {
                WordPickerView(
                    sourceText: sourceText,
                    phraseTranslation: translatedText,
                    isPhraseTranslationReady: isPhraseTranslationReady,
                    storage: storage,
                    onCancel: {
                        context.finish(translation: nil)
                    },
                    onSave: {
                        // Finish immediately after persistence so the system card
                        // closes without requiring a second interaction.
                        context.finish(translation: nil)
                    }
                )
                .transition(.opacity)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear(perform: loadCard)
        .translationTask(configuration) { session in
            await translate(with: session)
        }
    }

    private var isPhraseTranslationReady: Bool {
        status == .ready || status == .translationFailed
    }

    private var startupState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("正在准备单词卡片…")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 28)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func loadCard() {
        guard sourceText.isEmpty, let input = context.inputText else { return }
        let collapsed = String(input.characters)
            .split(whereSeparator: { $0.isNewline })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        sourceText = collapsed
        context.expandSheet()
        startTranslation()
    }

    private func startTranslation() {
        guard !sourceText.isEmpty else {
            status = .translationFailed
            return
        }
        status = .translating
        configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "zh-Hans")
        )
    }

    private func translate(with session: TranslationSession) async {
        guard status == .translating else { return }
        do {
            let response = try await session.translate(sourceText)
            translatedText = response.targetText
            status = .ready
            configuration = nil
        } catch {
            status = .translationFailed
            configuration = nil
        }
    }
}
