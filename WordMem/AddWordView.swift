import SwiftData
import SwiftUI

struct AddWordView: View {
    let dictionaryService: any DictionaryLookupService
    let completion: (AddWordOutcome) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var word = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    private var repository: WordbookRepository {
        WordbookRepository(modelContext: modelContext)
    }

    private var normalizedInput: String {
        WordInputNormalizer.normalizedKey(from: word)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("添加一个单词")
                        .font(.largeTitle.bold())

                    Text("音标、释义和词形会从本地词典自动补充。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                TextField("输入英文单词", text: $word)
                    .textFieldStyle(.roundedBorder)
                    .font(.title2)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.alphabet)
                    .submitLabel(.done)
                    .focused($isInputFocused)
                    .onSubmit(save)
                    .disabled(isSaving)
                    .accessibilityIdentifier("wordInputField")

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer(minLength: 0)

                Button(action: save) {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "plus.circle.fill")
                        }
                        Text(isSaving ? "正在补充" : "添加到单词本")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(normalizedInput.isEmpty || isSaving)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(.systemBackground))
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
        }
    }

    private func save() {
        let input = word
        guard !WordInputNormalizer.normalizedKey(from: input).isEmpty, !isSaving else { return }

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
