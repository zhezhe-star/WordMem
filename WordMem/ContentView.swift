import SwiftUI
import AVFoundation

struct Word: Identifiable {
    let id = UUID()
    let word: String
    let pronunciation: String
    let definition: String
    let example: String
    let meaning: String
    let tags: [String]

    init(word: String, pronunciation: String, definition: String, example: String, meaning: String, tags: [String]) {
        self.word = word
        self.pronunciation = pronunciation
        self.definition = definition
        self.example = example
        self.meaning = meaning
        self.tags = tags
    }
}

struct WordDetailView: View {
    let word: Word
    @State private var synthesizer = AVSpeechSynthesizer()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Word and pronunciation section
                VStack(alignment: .leading, spacing: 10) {
                    Text(word.word)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.blue)

                    Text(word.pronunciation)
                        .font(.title3)
                        .foregroundColor(.secondary)

                    if !word.meaning.isEmpty {
                        Text(word.meaning)
                            .font(.title3)
                            .foregroundColor(.primary)
                    }

                    if !word.tags.isEmpty {
                        HStack {
                            ForEach(word.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundColor(.blue)
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)

                // Play button
                Button(action: playWord) {
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title2)
                        Text("Play Pronunciation")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.vertical)

                // Definition section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Definition")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(word.definition)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

                // Example section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Example")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("\"\(word.example)\"")
                        .font(.body)
                        .italic()
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle("Word Detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func playWord() {
        let utterance = AVSpeechUtterance(string: word.word)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0

        synthesizer.speak(utterance)
    }
}

// MARK: - WordData Detail View
struct WordDataDetailView: View {
    let wordData: WordData
    @State private var synthesizer = AVSpeechSynthesizer()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Word and pronunciation section
                VStack(alignment: .leading, spacing: 10) {
                    Text(wordData.word)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.blue)

                    if let phonetic = wordData.phonetic, !phonetic.isEmpty {
                        Text(phonetic)
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }

                    Text(wordData.translation)
                        .font(.title3)
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)

                // Play button
                Button(action: playWord) {
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title2)
                        Text("播放发音")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.vertical)

                // Creation date
                VStack(alignment: .leading, spacing: 8) {
                    Text("创建日期")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(wordData.createDateString)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

                // Example section
                if let exampleSentence = wordData.exampleSentence, !exampleSentence.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("例句")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("\"\(exampleSentence)\"")
                            .font(.body)
                            .italic()
                            .foregroundColor(.secondary)

                        if let translatedExample = wordData.translatedExampleSentence, !translatedExample.isEmpty {
                            Text(translatedExample)
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }

                // Additional examples section
                if let example = wordData.example, !example.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("更多例句")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text(example)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }
            }
            .padding()
        }
        .navigationTitle("单词详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func playWord() {
        let utterance = AVSpeechUtterance(string: wordData.word)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0

        synthesizer.speak(utterance)
    }
}

struct ContentView: View {
    @StateObject private var storageManager = LocalStorageManager()
    @StateObject private var importManager = JSONImportManager()
    @State private var showingFilePicker = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""

    var body: some View {
        NavigationView {
            Group {
                if storageManager.isLoading {
                    ProgressView("加载中...")
                } else if storageManager.words.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)

                        Text("暂无单词")
                            .font(.title2)
                            .foregroundColor(.gray)

                        Text("点击右上角的导入按钮来添加单词")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List(storageManager.words) { wordData in
                        NavigationLink(destination: WordDataDetailView(wordData: wordData)) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(wordData.word)
                                        .font(.headline)
                                        .foregroundColor(.blue)

                                    Spacer()

                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                }

                                if let phonetic = wordData.phonetic, !phonetic.isEmpty {
                                    Text(phonetic)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Text(wordData.translation)
                                    .font(.caption)
                                    .foregroundColor(.primary)

                                if let example = wordData.exampleSentence, !example.isEmpty {
                                    Text(example)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("WordMem")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingFilePicker = true
                    }) {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
            }
            .sheet(isPresented: $showingFilePicker) {
                DocumentPickerView(
                    importManager: importManager,
                    storageManager: storageManager,
                    onImportComplete: { success, message in
                        alertTitle = success ? "导入成功" : "导入失败"
                        alertMessage = message
                        showingAlert = true
                    }
                )
            }
            .alert(isPresented: $showingAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("确定"))
                )
            }
        }
    }
}

// MARK: - 文件选择器视图
struct DocumentPickerView: UIViewControllerRepresentable {
    let importManager: JSONImportManager
    let storageManager: LocalStorageManager
    let onImportComplete: (Bool, String) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // 支持 JSON 和 TXT 文件
        let picker = UIDocumentPickerViewController(documentTypes: ["public.json", "public.text"], in: .import)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView

        init(_ parent: DocumentPickerView) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }

            parent.importManager.importJSON(from: url) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let words):
                    self.parent.storageManager.addWords(words, replaceExisting: true)
                    DispatchQueue.main.async {
                        self.parent.onImportComplete(true, "成功导入 \(words.count) 个单词")
                    }
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.parent.onImportComplete(false, error.localizedDescription)
                    }
                }
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // 用户取消选择
        }
    }
}

#Preview {
    ContentView()
}
