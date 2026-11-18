import SwiftUI
import Translation
import TranslationUIProvider

/// Presents one complete card: source, translation, phrase, and split words.
struct TranslationCardView: View {
    let context: any TranslationUIProviderContext

    @State private var sourceText = ""
    @State private var originalInput: AttributedString?
    @State private var translatedText = ""
    @State private var status: Status = .idle
    @State private var configuration: TranslationSession.Configuration?
    @State private var usesLowLatency = false
    @State private var showsFailureAlert = false

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
                        finishAfterSave(context: context)
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
        .alert("翻译暂时不可用", isPresented: $showsFailureAlert) {
            Button("重试") { startTranslation() }
            Button("退出", role: .cancel) {
                context.finish(translation: nil)
            }
        } message: {
            Text("请重试；退出会关闭翻译组件。")
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
        originalInput = input
        let collapsed = String(input.characters)
            .split(whereSeparator: { $0.isNewline })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        sourceText = collapsed
        context.expandSheet()
        startTranslation()
    }

    private func finishAfterSave(context: any TranslationUIProviderContext) {
        // Completing with the original text avoids a destructive replacement and
        // exercises the provider's successful-finish path on expanded sheets.
        context.finish(
            translation: TranslationProviderCloseRequest.savedCompletion(
                originalInput: originalInput ?? context.inputText,
                fallbackSourceText: sourceText
            )
        )
    }

    private func startTranslation() {
        guard !sourceText.isEmpty else {
            status = .translationFailed
            return
        }
        status = .translating
        usesLowLatency = false
        showsFailureAlert = false
        configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "zh-Hans")
        )
    }

    private func translate(with session: TranslationSession) async {
        guard status == .translating else { return }
        do {
            try await session.prepareTranslation()
            let response = try await session.translate(sourceText)
            translatedText = response.targetText
            status = .ready
            configuration = nil
        } catch {
            guard !Task.isCancelled else { return }
            if !usesLowLatency {
                usesLowLatency = true
                status = .translating
                configuration = lowLatencyConfiguration()
                return
            }
            status = .translationFailed
            configuration = nil
            showsFailureAlert = true
        }
    }

    private func lowLatencyConfiguration() -> TranslationSession.Configuration {
        let source = Locale.Language(identifier: "en")
        let target = Locale.Language(identifier: "zh-Hans")
        if #available(iOS 26.4, *) {
            return TranslationSession.Configuration(
                source: source,
                target: target,
                preferredStrategy: .lowLatency
            )
        }
        return TranslationSession.Configuration(source: source, target: target)
    }
}
