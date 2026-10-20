import SwiftUI
import Translation
import TranslationUIProvider

/// Mirrors the reference default-translation-app experience:
/// source sentence -> translation -> word picker -> save into the wordbook.
struct TranslationCardView: View {
    let context: any TranslationUIProviderContext

    @State private var sourceText = ""
    @State private var translatedText = ""
    @State private var status: Status = .idle
    @State private var configuration: TranslationSession.Configuration?
    @State private var showWordPicker = false

    private let storage = LocalStorageManager()

    enum Status: Equatable {
        case idle
        case translating
        case ready
        case translationFailed
        case saved
    }

    var body: some View {
        NavigationView {
            Group {
                if showWordPicker {
                    WordPickerView(
                        sourceText: sourceText,
                        phraseTranslation: translatedText,
                        storage: storage
                    ) {
                        withAnimation(.snappy) {
                            showWordPicker = false
                        }
                    } onSave: {
                        withAnimation(.snappy) {
                            status = .saved
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            context.finish(translation: nil)
                        }
                    }
                } else {
                    card
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .onAppear(perform: loadSource)
            .translationTask(configuration) { session in
                await translate(with: session)
            }
        }
        .navigationViewStyle(.stack)
    }

    private var card: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sourceSection
                translationSection
                importButton
                if status == .saved {
                    Label("已保存到 WordMem", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("原句")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(sourceText.isEmpty ? "正在获取选中文本…" : sourceText)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
        }
    }

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("翻译")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Group {
                if status == .translating {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在翻译…").foregroundStyle(.secondary)
                    }
                } else {
                    Text(translatedText.isEmpty ? " " : translatedText)
                        .font(.body)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)

            if status == .translationFailed {
                Label("系统翻译不可用，已保留原句，可直接挑选单词保存。", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            Button("重新翻译") {
                startTranslation()
            }
            .font(.footnote.weight(.semibold))
            .disabled(sourceText.isEmpty || status == .translating)
        }
    }

    private var importButton: some View {
        Button {
            context.expandSheet()
            withAnimation(.snappy) {
                showWordPicker = true
            }
        } label: {
            Text("导入到 WordMem")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .disabled(sourceText.isEmpty || status == .translating || status == .saved)
    }

    private func loadSource() {
        guard sourceText.isEmpty, let input = context.inputText else { return }
        let collapsed = String(input.characters)
            .split(whereSeparator: { $0.isNewline })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        sourceText = collapsed
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
