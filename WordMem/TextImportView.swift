import SwiftData

import SwiftUI
import Translation

struct TextImportView: View {
    let dictionary: any SystemDictionaryAuthorizing
    let completion: (WordImportSummary) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var sourceText = ""
    @State private var chips: [ImportCandidateChip] = []
    @State private var selection = ImportChipSelection(chips: [])
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var advisorToken = UUID()
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var translations: [String: String] = [:]
    @State private var phraseTranslation: String?
    @State private var isTranslating = false

#if DEBUG
    init(
        dictionary: any SystemDictionaryAuthorizing,
        completion: @escaping (WordImportSummary) -> Void,
        previewState: ImportPreviewState = ImportPreviewState()
    ) {
        self.dictionary = dictionary
        self.completion = completion
        _sourceText = State(initialValue: previewState.sourceText)
        _chips = State(initialValue: previewState.chips)
        _selection = State(
            initialValue: ImportPreviewFixtures.selection(
                for: previewState.chips,
                selectedOffsets: previewState.selectedOffsets
            )
        )
    }
#endif

    private var repository: WordbookRepository {
        WordbookRepository(modelContext: modelContext)
    }

    private var selectedWords: [String] {
        selection.selectedChips.map(\.text)
    }

    private var currentStep: ImportStep {
        chips.isEmpty ? .content : .selection
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ImportStepHeader(
                            currentStep: currentStep,
                            title: "文本导入",
                            subtitle: "输入英文内容，挑选要加入单词本的词。"
                        )

                        ImportSourceEditorCard(
                            title: "原文",
                            placeholder: "例如：The quick brown fox jumps over the lazy dog.",
                            text: $sourceText
                        )

                        if !sourceText.isEmpty {
                            ImportPhraseTranslationCard(
                                translation: phraseTranslation,
                                isTranslating: isTranslating && phraseTranslation == nil
                            )
                        }

                        if chips.isEmpty {
                            emptyState
                        } else {
                            selectionContent
                        }

                        if let errorMessage {
                            ImportErrorMessage(message: errorMessage)
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)

                ImportPrimaryCTA(
                    title: isTranslating
                        ? "正在翻译…"
                        : (isSaving ? "正在导入" : "导入 \(selectedWords.count) 个单词"),
                    isLoading: isSaving,
                    action: importSelectedWords
                )
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 14)
                .background(.bar)
                .disabled(selectedWords.isEmpty || isTranslating || isSaving)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("文本导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .onChange(of: sourceText, initial: true) {
                refreshCandidates()
            }
            .importCandidateTranslations(
                chips: chips,
                sourceText: sourceText,
                configuration: $translationConfiguration,
                translations: $translations,
                phraseTranslation: $phraseTranslation,
                isTranslating: $isTranslating
            )
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "还没有候选词",
            systemImage: "text.magnifyingglass",
            description: Text("输入英文内容后，这里会显示可选择单词。")
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var selectionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ImportSelectionToolbar(
                selectedCount: selection.selectedCount,
                totalCount: chips.count,
                onSelectAll: { selection.selectAll() },
                onClear: { selection.clear() }
            )

            ImportCandidateChipGrid(
                chips: chips,
                selection: $selection,
                meanings: translations,
                isTranslating: isTranslating,
                onRestoreOriginal: restoreOriginal
            )
        }
    }

    private func refreshCandidates() {
        let token = UUID()
        advisorToken = token
        phraseTranslation = nil
        let context = sourceText

        Task {
            let candidates = EnglishWordCandidateSplitter.candidates(from: context)
            let refreshedChips = await ImportCandidatePipeline.chips(
                from: candidates,
                context: context
            )
            guard advisorToken == token else { return }
            chips = refreshedChips
            selection.updateChips(refreshedChips)
            translationConfiguration = ImportCandidateTranslationModifier
                .refreshedConfiguration(translationConfiguration)
        }
    }

    private func restoreOriginal(_ chip: ImportCandidateChip) {
        let restored = chip.restoringOriginal()
        chips = chips.map { $0.id == chip.id ? restored : $0 }
        selection.updateChips(chips)
        if let translation = translations[chip.id] {
            translations[restored.id] = translation
        }
    }

    private func importSelectedWords() {
        guard !selectedWords.isEmpty, !isSaving else { return }

        isSaving = true
        errorMessage = nil

        Task {
            defer { isSaving = false }

            do {
                let submission = WordImportSubmission(
                    source: .text,
                    sourceText: sourceText,
                    candidates: ImportCandidatePipeline.payloads(
                        from: selection.selectedChips,
                        translations: translations
                    ),
                    metadata: phraseTranslationMetadata
                )
                let outcomes = try await repository.importSubmission(
                    submission,
                    using: dictionary
                )
                completion(WordImportSummary(outcomes: outcomes))
                dismiss()
            } catch {
                errorMessage = "批量导入失败，请重试。"
            }
        }
    }

    private var phraseTranslationMetadata: [String: String] {
        var metadata = ["channel": WordImportSource.text.rawValue]
        if let phraseTranslation, !phraseTranslation.isEmpty {
            metadata["phraseTranslation"] = phraseTranslation
        }
        return metadata
    }
}

#if DEBUG
#Preview("文本导入 · 空状态") {
    TextImportView(dictionary: UIKitSystemDictionaryAuthorizer()) { _ in }
}

#Preview("文本导入 · 正常候选") {
    TextImportView(
        dictionary: UIKitSystemDictionaryAuthorizer(),
        completion: { _ in },
        previewState: ImportPreviewState(
            sourceText: ImportPreviewFixtures.text(count: 8),
            chips: ImportPreviewFixtures.chips(count: 8),
            selectedOffsets: [1, 4]
        )
    )
}

#Preview("文本导入 · 55 个候选") {
    TextImportView(
        dictionary: UIKitSystemDictionaryAuthorizer(),
        completion: { _ in },
        previewState: ImportPreviewState(
            sourceText: ImportPreviewFixtures.text(count: 55),
            chips: ImportPreviewFixtures.chips(count: 55),
            selectedOffsets: [0, 27, 54]
        )
    )
}
#endif
