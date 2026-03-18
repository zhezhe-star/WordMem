import Foundation
import SwiftUI

struct WordData: Identifiable, Codable {
    var id: UUID = UUID()
    var word: String
    var translation: String
    var phonetic: String?
    var createDateString: String
    var example: String?
    var exampleSentence: String?
    var translatedExampleSentence: String?
    var createdAt: Date

    // 用于兼容旧的初始化方法
    init(word: String, translation: String, phonetic: String? = nil, createDateString: String = "", example: String? = nil, exampleSentence: String? = nil, translatedExampleSentence: String? = nil) {
        self.word = word
        self.translation = translation
        self.phonetic = phonetic
        self.createDateString = createDateString
        self.example = example
        self.exampleSentence = exampleSentence
        self.translatedExampleSentence = translatedExampleSentence
        self.createdAt = Date()
    }

    // 用于 JSON 导入的初始化
    init(originText: String, translation: String, phonetic: String? = nil, createDateString: String = "", example: String? = nil, exampleSentence: String? = nil, translatedExampleSentence: String? = nil) {
        self.word = originText
        self.translation = translation
        self.phonetic = phonetic
        self.createDateString = createDateString
        self.example = example
        self.exampleSentence = exampleSentence
        self.translatedExampleSentence = translatedExampleSentence
        self.createdAt = Date()
    }

    // CodingKeys 用于映射 JSON 字段名
    enum CodingKeys: String, CodingKey {
        case id
        case word = "originText"
        case translation
        case phonetic
        case createDateString
        case example
        case exampleSentence
        case translatedExampleSentence
        case createdAt
    }
}
