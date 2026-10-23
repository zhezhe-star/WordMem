import SwiftData
import SwiftUI

struct AddWordView: View {
    let dictionary: any SystemDictionaryAuthorizing
    let completion: (AddWordOutcome) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var word = ""
    @State private var selection = ImportChipSelection(chips: [])
    @State private var advisorChips: [ImportCandidateChip] = []
    @State private var advisorToken = UUID()
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var userTranslation = ""
    @State private var userExample = ""
    @State private var userNote = ""
    @FocusState private var isInputFocused: Bool

#if DEBUG
    init(
        dictionary: any SystemDictionaryAuthorizing,
        completion: @escaping (AddWordOutcome) -> Void,
        previewState: ImportPreviewState = ImportPreviewState()
    ) {
        self.dictionary = dictionary
        self.completion = completion
        _word = State(initialValue: previewState.word)
        let normalizedWord = WordInputNormalizer.normalizedKey(from: previewState.word)
        let initialChips = normalizedWord.isEmpty
            ? []
            : [ImportCandidateChip(id: normalizedWord, text: previewState.word, sourceOrder: 0)]
        _advisorChips = State(initialValue: initialChips)
        _selection = State(
            initialValue: ImportPreviewFixtures.selection(
                for: initialChips,
                selectedOffsets: previewState.selectedOffsets
            )
        )
    }
#endif

    private var repository: WordbookRepository {
        WordbookRepository(modelContext: modelContext)
    }

    private var normalizedInput: String {
        WordInputNormalizer.normalizedKey(from: word)
    }

    private var currentStep: ImportStep {
        advisorChips.isEmpty ? .content : .selection
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ImportStepHeader(
                            currentStep: currentStep,
                            title: "添加一个单词",
                            subtitle: "单词保存后，可随时在系统词典中查看释义和发音。"
                        )

                        inputCard

                        if advisorChips.isEmpty {
                            ContentUnavailableView(
                                "输入后挑选单词",
                                systemImage: "square.and.pencil",
                                description: Text("输入英文单词后，它会显示为可确认的选择。")
                            )
                            .padding(.vertical, 28)
                        } else {
                            selectionContent
                        }

                        if !advisorChips.isEmpty {
                            userFields
                        }

                        if let errorMessage {
                            ImportErrorMessage(message: errorMessage)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollBounceBehavior(.basedOnSize)

                ImportPrimaryCTA(
                    title: isSaving ? "正在补充" : "添加 \(selection.selectedCount) 个单词",
                    isLoading: isSaving,
                    action: save
                )
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 14)
                .background(.bar)
                .disabled(selection.selectedCount == 0 || isSaving)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("添加单词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .task {
                isInputFocused = true
            }
            .onChange(of: word, initial: true) {
                refreshCandidate()
            }
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("单词")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("输入英文单词", text: $word)
                .font(.title3.weight(.medium))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.alphabet)
                .submitLabel(.done)
                .focused($isInputFocused)
                .onSubmit(save)
                .disabled(isSaving)
                .padding(13)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
                .accessibilityIdentifier("wordInputField")
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
        }
    }

    private var userFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("用户字段（可选）")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("我的翻译", text: $userTranslation)
            TextField("我的例句", text: $userExample)
            TextField("我的笔记", text: $userNote)
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 22))
    }

    private var selectionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ImportSelectionToolbar(
                selectedCount: selection.selectedCount,
                totalCount: advisorChips.count,
                onSelectAll: { selection.selectAll() },
                onClear: { selection.clear() }
            )

            ImportCandidateChipGrid(
                chips: advisorChips,
                selection: $selection,
                onRestoreOriginal: restoreOriginal
            )
        }
    }

    private func refreshCandidate() {
        let token = UUID()
        advisorToken = token
        let rawWord = word
        guard !WordInputNormalizer.normalizedKey(from: rawWord).isEmpty else {
            advisorChips = []
            selection = ImportChipSelection(chips: [])
            return
        }

        Task {
            let candidate = WordImportCandidate(
                text: rawWord,
                normalizedKey: WordInputNormalizer.normalizedKey(from: rawWord)
            )
            let advisedChips = await ImportWordAdvisor.live().chips(
                from: [candidate],
                context: nil
            )
            guard advisorToken == token else { return }
            advisorChips = advisedChips
            selection = ImportChipSelection(chips: advisedChips)
        }
    }

    private func restoreOriginal(_ chip: ImportCandidateChip) {
        let restored = chip.restoringOriginal()
        advisorChips = advisorChips.map { $0.id == chip.id ? restored : $0 }
        selection = ImportChipSelection(chips: advisorChips)
    }

    private func save() {
        let input = word
        guard selection.selectedCount > 0, !normalizedInput.isEmpty, !isSaving else { return }

        isSaving = true
        errorMessage = nil

        Task {
            defer { isSaving = false }

            do {
                var candidates = ImportCandidatePipeline.payloads(from: selection.selectedChips)
                if var candidate = candidates.first {
                    candidate.userTranslation = emptyAsNil(userTranslation)
                    candidate.userExample = emptyAsNil(userExample)
                    candidate.userNote = emptyAsNil(userNote)
                    candidates[0] = candidate
                }
                let submission = WordImportSubmission(
                    source: .manual,
                    sourceText: input,
                    candidates: candidates,
                    metadata: ["channel": WordImportSource.manual.rawValue]
                )
                let outcomes = try await repository.importSubmission(
                    submission,
                    using: dictionary
                )
                guard let outcome = outcomes.first else {
                    throw WordImportError.emptySelection
                }
                completion(outcome)
                dismiss()
            } catch {
                errorMessage = "保存失败，请重试。"
            }
        }
    }

    private func emptyAsNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
