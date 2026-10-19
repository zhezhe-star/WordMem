import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct WordDataDetailView: View {
    let wordData: WordData
    @State private var synthesizer = AVSpeechSynthesizer()

    var body: some View {
        List {
            Section {
                Text(wordData.word)
                    .font(.largeTitle.bold())
                    .textSelection(.enabled)

                if let phonetic = wordData.phonetic {
                    Text(phonetic)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Button {
                    playWord()
                } label: {
                    Label("播放发音", systemImage: "speaker.wave.2")
                }
            }

            Section("解释") {
                Text(wordData.translation)
                    .textSelection(.enabled)
            }

            Section("创建日期") {
                Text(wordData.createDateString)
                    .foregroundStyle(.secondary)
            }

            if let exampleSentence = wordData.exampleSentence {
                Section("例句") {
                    Text(exampleSentence)
                        .textSelection(.enabled)

                    if let translatedExampleSentence = wordData.translatedExampleSentence {
                        Text(translatedExampleSentence)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let example = wordData.example {
                Section("补充例句") {
                    Text(example)
                        .textSelection(.enabled)
                }
            }

            if let note = wordData.note {
                Section("笔记") {
                    Text(note)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(wordData.word)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func playWord() {
        let utterance = AVSpeechUtterance(string: wordData.word)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        synthesizer.speak(utterance)
    }
}

struct ContentView: View {
    @StateObject private var storageManager = LocalStorageManager()
    @StateObject private var importManager = JSONImportManager()
    @State private var activeImportMode: ImportMode?
    @State private var importOutcome: ImportOutcome?
    @State private var savedWord: WordData?

    private enum ImportMode: String, Identifiable {
        case manual
        case json

        var id: String { rawValue }
    }

    private struct ImportOutcome: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        NavigationView {
            Group {
                if storageManager.words.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 56))
                            .foregroundStyle(.secondary)

                        Text("暂无单词")
                            .font(.title2.bold())

                        Text("添加一个单词，或导入 JSON 单词本")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List(storageManager.words) { wordData in
                        NavigationLink(destination: WordDataDetailView(wordData: wordData)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(wordData.word)
                                    .font(.headline)

                                if let phonetic = wordData.phonetic {
                                    Text(phonetic)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Text(wordData.translation)
                                    .font(.subheadline)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("WordMem")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            activeImportMode = .manual
                        } label: {
                            Label("添加单词", systemImage: "character.book.closed")
                        }

                        Button {
                            activeImportMode = .json
                        } label: {
                            Label("导入 JSON", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加或导入单词")
                    .disabled(importManager.isImporting)
                }
            }
        }
        .onOpenURL { url in
            guard url.absoluteString == "wordmem://saved" else { return }
            storageManager.loadWords()
            savedWord = storageManager.words.max { $0.createdAt < $1.createdAt }
        }
        .sheet(item: $savedWord) { word in
            NavigationView {
                WordDataDetailView(wordData: word)
            }
        }
        .sheet(item: $activeImportMode) { mode in
            if mode == .manual {
                AddWordView(storageManager: storageManager)
            }
        }
        .fileImporter(
            isPresented: Binding(
                get: { activeImportMode == .json },
                set: { isPresented in
                    if !isPresented {
                        activeImportMode = nil
                    }
                }
            ),
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleJSONImport(result)
        }
        .alert(item: $importOutcome) { outcome in
            Alert(
                title: Text(outcome.title),
                message: Text(outcome.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private func handleJSONImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                importOutcome = ImportOutcome(
                    title: "导入失败",
                    message: "未选择 JSON 文件。"
                )
                return
            }

            importManager.importJSON(from: url) { importResult in
                switch importResult {
                case .success(let words):
                    storageManager.addWords(words, replaceExisting: true)
                    importOutcome = ImportOutcome(
                        title: "导入成功",
                        message: "已导入 \(words.count) 个单词。"
                    )
                case .failure(let error):
                    importOutcome = ImportOutcome(
                        title: "导入失败",
                        message: error.localizedDescription
                    )
                }
            }
        case .failure(let error):
            importOutcome = ImportOutcome(
                title: "导入失败",
                message: error.localizedDescription
            )
        }
    }
}

#Preview {
    ContentView()
}
