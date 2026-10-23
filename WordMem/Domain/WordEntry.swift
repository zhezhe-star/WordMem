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
    var systemDictionaryAvailable: Bool
    var userTranslation: String
    var userExample: String?
    var userNote: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        localeIdentifier: String = WordIdentity.defaultLocaleIdentifier,
        normalizedKey: String,
        headword: String,
        originalText: String,
        systemDictionaryAvailable: Bool = false,
        userTranslation: String = "",
        userExample: String? = nil,
        userNote: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.localeIdentifier = localeIdentifier
        self.normalizedKey = normalizedKey
        self.headword = headword
        self.originalText = originalText
        self.systemDictionaryAvailable = systemDictionaryAvailable
        self.userTranslation = userTranslation
        self.userExample = userExample
        self.userNote = userNote
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
