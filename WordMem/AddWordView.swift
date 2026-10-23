import SwiftData
import SwiftUI

struct AddWordView: View {
    let dictionaryService: any DictionaryLookupService
    let completion: (AddWordOutcome) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var word = ""
    @State private var selection = ImportChipSelection(chips: [])
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    private var repository: WordbookRepository {
        WordbookRepository(modelContext: modelContext)
    }

    private var normalizedInput: String {
        WordInputNormalizer.normalizedKey(from: word)
    }

    private var chips: [ImportCandidateChip] {
        guard !normalizedInput.isEmpty else { return [] }
        return [ImportCandidateChip(id: normalizedInput, text: word, sourceOrder: 0)]
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
                            title: "添加一个单词",
                            subtitle: "音标、释义和词形会从本地词典自动补充。"
                        )

                        inputCard

                        if chips.isEmpty {
                            ContentUnavailableView(
                                "输入后挑选单词",
                                systemImage: "square.and.pencil",
                                description: Text("输入英文单词后，它会显示为可确认的选择。")
                            )
                            .padding(.vertical, 28)
                        } else {
                            selectionContent
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
            .onChange(of: normalizedInput) {
                selection = ImportChipSelection(chips: chips)
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

    private func save() {
        let input = word
        guard selection.selectedCount > 0, !normalizedInput.isEmpty, !isSaving else { return }

        isSaving = true
        errorMessage = nil

        Task {
            defer { isSaving = false }

            do {
                let submission = WordImportSubmission(
                    source: .manual,
                    sourceText: input,
                    candidates: [
                        WordImportCandidatePayload(
                            text: input,
                            normalizedKey: WordInputNormalizer.normalizedKey(from: input)
                        )
                    ],
                    metadata: ["channel": WordImportSource.manual.rawValue]
                )
                let outcomes = try await repository.importSubmission(
                    submission,
                    using: dictionaryService
                )
                guard let outcome = outcomes.first else {
                    throw WordImportError.emptySelection
                }
                completion(outcome)
                dismiss()
            } catch {
                errorMessage = "本地词典补充失败，请重试。"
            }
        }
    }
}
