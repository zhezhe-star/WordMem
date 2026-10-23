import SwiftData

import SwiftUI

struct TextImportView: View {
    let dictionaryService: any DictionaryLookupService
    let completion: (WordImportSummary) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var sourceText = ""
    @State private var chips: [ImportCandidateChip] = []
    @State private var selection = ImportChipSelection(chips: [])
    @State private var isSaving = false
    @State private var errorMessage: String?

#if DEBUG
    init(
        dictionaryService: any DictionaryLookupService,
        completion: @escaping (WordImportSummary) -> Void,
        previewState: ImportPreviewState = ImportPreviewState()
    ) {
        self.dictionaryService = dictionaryService
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
                    title: isSaving ? "正在导入" : "导入 \(selectedWords.count) 个单词",
                    isLoading: isSaving,
                    action: importSelectedWords
                )
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 14)
                .background(.bar)
                .disabled(selectedWords.isEmpty || isSaving)
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

            ImportCandidateChipGrid(chips: chips, selection: $selection)
        }
    }

    private func refreshCandidates() {
        let candidates = EnglishWordCandidateSplitter.candidates(from: sourceText)
        let refreshedChips = ImportCandidateAdapter.chips(from: candidates)
        chips = refreshedChips
        selection.updateChips(refreshedChips)
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
                    candidates: selectedWords.map {
                        WordImportCandidatePayload(
                            text: $0,
                            normalizedKey: WordInputNormalizer.normalizedKey(from: $0)
                        )
                    },
                    metadata: ["channel": WordImportSource.text.rawValue]
                )
                let outcomes = try await repository.importSubmission(
                    submission,
                    using: dictionaryService
                )
                completion(WordImportSummary(outcomes: outcomes))
                dismiss()
            } catch {
                errorMessage = "批量导入失败，请重试。"
            }
        }
    }
}

#if DEBUG
#Preview("文本导入 · 空状态") {
    TextImportView(dictionaryService: SystemDictionaryLookupService()) { _ in }
}

#Preview("文本导入 · 正常候选") {
    TextImportView(
        dictionaryService: SystemDictionaryLookupService(),
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
        dictionaryService: SystemDictionaryLookupService(),
        completion: { _ in },
        previewState: ImportPreviewState(
            sourceText: ImportPreviewFixtures.text(count: 55),
            chips: ImportPreviewFixtures.chips(count: 55),
            selectedOffsets: [0, 27, 54]
        )
    )
}
#endif
