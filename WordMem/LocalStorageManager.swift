import Foundation
import SwiftUI

class LocalStorageManager: ObservableObject {
    private let userDefaults = UserDefaults.standard
    private let wordsKey = "saved_words"

    @Published var words: [WordData] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    init() {
        loadWords()
    }

    // MARK: - 保存单词列表
    func saveWords(_ words: [WordData]) {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(words)
                self.userDefaults.set(data, forKey: self.wordsKey)

                DispatchQueue.main.async {
                    self.words = words
                    self.isLoading = false
                    self.errorMessage = nil
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "保存失败: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - 加载单词列表
    func loadWords() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            guard let data = self.userDefaults.data(forKey: self.wordsKey) else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.words = []
                }
                return
            }

            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let decodedWords = try decoder.decode([WordData].self, from: data)

                DispatchQueue.main.async {
                    self.words = decodedWords
                    self.isLoading = false
                    self.errorMessage = nil
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "加载失败: \(error.localizedDescription)"
                    self.words = []
                }
            }
        }
    }

    // MARK: - 添加单个单词
    func addWord(_ word: WordData) {
        var updatedWords = words
        // 检查是否已存在，如果存在则覆盖
        if let index = updatedWords.firstIndex(where: { $0.word == word.word }) {
            updatedWords[index] = word
        } else {
            updatedWords.append(word)
        }
        saveWords(updatedWords)
    }

    // MARK: - 批量添加单词（导入时使用）
    func addWords(_ newWords: [WordData], replaceExisting: Bool = true) {
        var updatedWords = words

        for newWord in newWords {
            if let index = updatedWords.firstIndex(where: { $0.word == newWord.word }) {
                // 如果存在且需要替换，则覆盖
                if replaceExisting {
                    updatedWords[index] = newWord
                }
            } else {
                // 不存在则添加
                updatedWords.append(newWord)
            }
        }

        saveWords(updatedWords)
    }

    // MARK: - 删除单词
    func deleteWord(_ word: WordData) {
        let updatedWords = words.filter { $0.id != word.id }
        saveWords(updatedWords)
    }

    // MARK: - 清空所有单词
    func clearAllWords() {
        saveWords([])
    }

    // MARK: - 获取单词数量
    var wordCount: Int {
        return words.count
    }
}
