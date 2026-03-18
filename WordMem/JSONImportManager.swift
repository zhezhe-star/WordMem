import Foundation
import SwiftUI

class JSONImportManager: ObservableObject {
    @Published var isImporting = false
    @Published var importMessage = ""
    @Published var importSuccess = false
    @Published var importedWordCount = 0

    // MARK: - 从文件 URL 导入 JSON
    func importJSON(from fileURL: URL, completion: @escaping (Result<[WordData], Error>) -> Void) {
        isImporting = true
        importMessage = "正在读取文件..."
        importSuccess = false
        importedWordCount = 0

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                // 1. 读取文件内容
                guard fileURL.startAccessingSecurityScopedResource() else {
                    throw ImportError.fileAccessDenied
                }

                let data = try Data(contentsOf: fileURL)
                fileURL.stopAccessingSecurityScopedResource()

                // 2. 解析 JSON
                DispatchQueue.main.async {
                    self.importMessage = "正在解析 JSON..."
                }

                let decoder = JSONDecoder()
                var words = try decoder.decode([WordData].self, from: data)

                // 3. 验证数据
                DispatchQueue.main.async {
                    self.importMessage = "正在验证数据..."
                }

                words = self.validateWords(words)

                // 4. 完成
                DispatchQueue.main.async {
                    self.isImporting = false
                    self.importSuccess = true
                    self.importedWordCount = words.count
                    self.importMessage = "成功导入 \(words.count) 个单词"
                    completion(.success(words))
                }

            } catch {
                DispatchQueue.main.async {
                    self.isImporting = false
                    self.importSuccess = false
                    self.importMessage = "导入失败: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - 验证和清理单词数据
    private func validateWords(_ words: [WordData]) -> [WordData] {
        return words.compactMap { word -> WordData? in
            // 验证必填字段
            guard !word.word.isEmpty && !word.translation.isEmpty else {
                return nil
            }

            // 创建清理后的单词对象
            var validatedWord = word

            // 确保 createdAt 有值
            if validatedWord.createdAt == Date.distantPast {
                validatedWord.createdAt = Date()
            }

            // 清理空字符串的可选字段
            if validatedWord.phonetic?.isEmpty == true {
                validatedWord.phonetic = nil
            }
            if validatedWord.example?.isEmpty == true {
                validatedWord.example = nil
            }
            if validatedWord.exampleSentence?.isEmpty == true {
                validatedWord.exampleSentence = nil
            }
            if validatedWord.translatedExampleSentence?.isEmpty == true {
                validatedWord.translatedExampleSentence = nil
            }
            if validatedWord.createDateString.isEmpty {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                validatedWord.createDateString = dateFormatter.string(from: Date())
            }

            return validatedWord
        }
    }

    // MARK: - 从字符串导入 JSON（用于测试）
    func importJSON(from jsonString: String, completion: @escaping (Result<[WordData], Error>) -> Void) {
        guard let data = jsonString.data(using: .utf8) else {
            completion(.failure(ImportError.invalidData))
            return
        }

        do {
            let decoder = JSONDecoder()
            let words = try decoder.decode([WordData].self, from: data)
            let validatedWords = validateWords(words)
            completion(.success(validatedWords))
        } catch {
            completion(.failure(error))
        }
    }
}

// MARK: - 导入错误类型
enum ImportError: LocalizedError {
    case fileAccessDenied
    case invalidData
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .fileAccessDenied:
            return "无法访问文件，请检查文件权限"
        case .invalidData:
            return "文件数据无效"
        case .invalidFormat:
            return "JSON 格式不正确"
        }
    }
}
