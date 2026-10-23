import Foundation
import SwiftData

@Model
final class WordEntry {
    #Unique<WordEntry>([\.normalizedKey])

    var id: UUID
    var originalInput: String
    @Attribute(.unique) var normalizedKey: String
    var headword: String
    var phonetic: String?
    var translation: String
    var userTranslation: String = ""
    var legacyExample: String?
    var userExample: String?
    var legacyExampleSentence: String?
    var legacyTranslatedExampleSentence: String?
    private var sensesData: Data
    private var formsData: Data
    private var tagsData: Data
    var lookupStatusRawValue: String
    var dictionaryID: String?
    var dictionaryVersion: String?
    var createdAt: Date
    var updatedAt: Date

    var senses: [WordSense] {
        get { Self.decode(sensesData, fallback: []) }
        set { sensesData = Self.encode(newValue) }
    }

    var forms: [WordForm] {
        get { Self.decode(formsData, fallback: []) }
        set { formsData = Self.encode(newValue) }
    }

    var tags: [String] {
        get { Self.decode(tagsData, fallback: []) }
        set { tagsData = Self.encode(newValue) }
    }

    var lookupStatus: LookupStatus {
        get { LookupStatus(rawValue: lookupStatusRawValue) ?? .notFound }
        set { lookupStatusRawValue = newValue.rawValue }
    }

    var displayTranslation: String {
        translation.isEmpty ? userTranslation : translation
    }

    var hasLegacyUserData: Bool {
        !userTranslation.isEmpty
            || legacyExample != nil
            || legacyExampleSentence != nil
            || legacyTranslatedExampleSentence != nil
    }

    init(
        id: UUID = UUID(),
        originalInput: String,
        normalizedKey: String,
        headword: String,
        phonetic: String? = nil,
        translation: String = "",
        userTranslation: String = "",
        legacyExample: String? = nil,
        userExample: String? = nil,
        legacyExampleSentence: String? = nil,
        legacyTranslatedExampleSentence: String? = nil,
        senses: [WordSense] = [],
        forms: [WordForm] = [],
        tags: [String] = [],
        lookupStatus: LookupStatus = .notFound,
        dictionaryID: String? = nil,
        dictionaryVersion: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.originalInput = originalInput
        self.normalizedKey = normalizedKey
        self.headword = headword
        self.phonetic = phonetic
        self.translation = translation
        self.userTranslation = userTranslation
        self.legacyExample = legacyExample
        self.userExample = userExample
        self.legacyExampleSentence = legacyExampleSentence
        self.legacyTranslatedExampleSentence = legacyTranslatedExampleSentence
        self.sensesData = WordEntry.encode(senses)
        self.formsData = WordEntry.encode(forms)
        self.tagsData = WordEntry.encode(tags)
        self.lookupStatusRawValue = lookupStatus.rawValue
        self.dictionaryID = dictionaryID
        self.dictionaryVersion = dictionaryVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func apply(_ result: DictionaryLookupResult, now: Date = .now) {
        guard let entry = result.entry else { return }

        originalInput = result.originalInput
        headword = entry.headword
        phonetic = entry.phonetic
        translation = entry.primaryTranslation
        senses = entry.senses
        forms = entry.forms
        tags = entry.tags
        lookupStatus = result.status
        dictionaryID = entry.id
        dictionaryVersion = entry.dictionaryVersion
        updatedAt = now
    }

    private static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    private static func decode<T: Decodable>(_ data: Data, fallback: T) -> T {
        guard !data.isEmpty else { return fallback }
        return (try? JSONDecoder().decode(T.self, from: data)) ?? fallback
    }
}
