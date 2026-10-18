import SwiftUI

struct AddWordView: View {
    @ObservedObject var storageManager: LocalStorageManager
    @Environment(\.dismiss) private var dismiss

    @State private var word = ""
    @State private var translation = ""
    @State private var phonetic = ""
    @State private var exampleSentence = ""
    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case word
        case translation
        case phonetic
        case exampleSentence
    }

    private var canSave: Bool {
        !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                Section("单词") {
                    TextField("要记住的单词", text: $word)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .word)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .phonetic }

                    TextField("音标", text: $phonetic)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .phonetic)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .translation }
                }

                Section("解释") {
                    TextField("释义", text: $translation)
                        .focused($focusedField, equals: .translation)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .exampleSentence }
                        .onSubmit { focusedField = .exampleSentence }

                    TextField("例句", text: $exampleSentence)
                        .focused($focusedField, equals: .exampleSentence)
                        .submitLabel(.done)
                }
            }
            .navigationTitle("添加单词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                focusedField = .word
            }
        }
    }

    private func save() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let newWord = WordData(
            word: word.trimmingCharacters(in: .whitespacesAndNewlines),
            translation: translation.trimmingCharacters(in: .whitespacesAndNewlines),
            phonetic: normalized(phonetic),
            createDateString: formatter.string(from: Date()),
            exampleSentence: normalized(exampleSentence)
        )

        storageManager.addWord(newWord)
        dismiss()
    }

    private func normalized(_ value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

struct AddWordView_Previews: PreviewProvider {
    static var previews: some View {
        AddWordView(storageManager: LocalStorageManager(defaults: UserDefaults(suiteName: "AddWordPreview")))
    }
}
