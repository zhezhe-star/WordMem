import Foundation
import SwiftUI

class LocalStorageManager: ObservableObject {
    static let appGroupSuiteName = "group.com.zhezhe.wordmem"
    static let migrationCompletedKey = "did_migrate_standard_saved_words"

    private let userDefaults: UserDefaults
    private let wordsKey: String
    private let legacyDefaults: UserDefaults?

    @Published var words: [WordData] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    convenience init(defaults: UserDefaults? = nil) {
        self.init(
            defaults: defaults,
            legacyDefaults: defaults == nil ? .standard : nil,
            wordsKey: "saved_words"
        )
    }

    init(
        defaults: UserDefaults? = nil,
        legacyDefaults: UserDefaults? = nil,
        wordsKey: String = "saved_words"
    ) {
        if let defaults {
            self.userDefaults = defaults
        } else {
            self.userDefaults = UserDefaults(suiteName: Self.appGroupSuiteName) ?? .standard
        }
        self.legacyDefaults = legacyDefaults
        self.wordsKey = wordsKey
        migrateLegacyStandardDefaultsIfNeeded()
        loadWords()
    }

    private func migrateLegacyStandardDefaultsIfNeeded() {
        guard let legacyDefaults else { return }
        guard !userDefaults.bool(forKey: Self.migrationCompletedKey) else { return }

        if userDefaults.data(forKey: wordsKey) == nil,
           let legacyData = legacyDefaults.data(forKey: wordsKey),
           !legacyData.isEmpty {
            userDefaults.set(legacyData, forKey: wordsKey)
        }

        userDefaults.set(true, forKey: Self.migrationCompletedKey)
    }

    // MARK: - 保存单词列表
    func saveWords(_ words: [WordData]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(words)
            userDefaults.set(data, forKey: wordsKey)
            self.words = words
            isLoading = false
            errorMessage = nil
        } catch {
            isLoading = false
            errorMessage = "保存失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 加载单词列表
    func loadWords() {
        guard let data = userDefaults.data(forKey: wordsKey) else {
            isLoading = false
            words = []
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            words = try decoder.decode([WordData].self, from: data)
            isLoading = false
            errorMessage = nil
        } catch {
            isLoading = false
            errorMessage = "加载失败: \(error.localizedDescription)"
            words = []
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
