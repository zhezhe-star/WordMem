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
    var note: String?
    var createdAt: Date

    // 用于兼容旧的初始化方法
    init(
        word: String,
        translation: String,
        phonetic: String? = nil,
        createDateString: String = "",
        example: String? = nil,
        exampleSentence: String? = nil,
        translatedExampleSentence: String? = nil,
        note: String? = nil,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) {
        self.word = word
        self.translation = translation
        self.phonetic = phonetic
        self.createDateString = createDateString
        self.example = example
        self.exampleSentence = exampleSentence
        self.translatedExampleSentence = translatedExampleSentence
        self.note = note
        self.id = id
        self.createdAt = createdAt
    }

    // 用于 JSON 导入的初始化
    init(
        originText: String,
        translation: String,
        phonetic: String? = nil,
        createDateString: String = "",
        example: String? = nil,
        exampleSentence: String? = nil,
        translatedExampleSentence: String? = nil,
        note: String? = nil
    ) {
        self.init(
            word: originText,
            translation: translation,
            phonetic: phonetic,
            createDateString: createDateString,
            example: example,
            exampleSentence: exampleSentence,
            translatedExampleSentence: translatedExampleSentence,
            note: note
        )
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
        case note
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Older saved data and some hand-edited JSON files omit optional fields.
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        word = try container.decode(String.self, forKey: .word)
        translation = try container.decode(String.self, forKey: .translation)
        phonetic = try container.decodeIfPresent(String.self, forKey: .phonetic)
        createDateString = try container.decodeIfPresent(String.self, forKey: .createDateString) ?? ""
        example = try container.decodeIfPresent(String.self, forKey: .example)
        exampleSentence = try container.decodeIfPresent(String.self, forKey: .exampleSentence)
        translatedExampleSentence = try container.decodeIfPresent(
            String.self,
            forKey: .translatedExampleSentence
        )
        note = try container.decodeIfPresent(String.self, forKey: .note)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

/// Turns a selected source sentence into the individual word chips shown by
/// the translation provider. Keep this pure so picker behavior stays testable.
enum TranslationWordTokenizer {
    static func wordChips(from source: String) -> [String] {
        var seen = Set<String>()
        return source
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
            .filter { word in
                !word.isEmpty && word.range(of: "[a-zA-Z]", options: .regularExpression) != nil
            }
            .filter { seen.insert($0).inserted }
    }
}
