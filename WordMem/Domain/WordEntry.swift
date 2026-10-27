import Foundation
import SwiftData

@Model
final class WordEntry {
    #Unique<WordEntry>([\.localeIdentifier, \.normalizedKey])

    var id: UUID
    var localeIdentifier: String
    var normalizedKey: String
    var headword: String
    var originalText: String
    var translation: String
    var example: String?
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        localeIdentifier: String = WordIdentity.defaultLocaleIdentifier,
        normalizedKey: String,
        headword: String,
        originalText: String,
        translation: String = "",
        example: String? = nil,
        note: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.localeIdentifier = localeIdentifier
        self.normalizedKey = normalizedKey
        self.headword = headword
        self.originalText = originalText
        self.translation = translation
        self.example = example
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
