import Foundation

enum LookupStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case enriched
    case lemmaResolved
    case autoCorrected
    case ambiguousResolved
    case userSaved
    case notFound

    var displayName: String {
        switch self {
        case .enriched: "已收录"
        case .lemmaResolved: "已还原原形"
        case .autoCorrected: "已自动纠正"
        case .ambiguousResolved: "已选择词义"
        case .userSaved: "已补充"
        case .notFound: "待补充"
        }
    }
}

struct WordSense: Codable, Hashable, Sendable {
    var partOfSpeech: String?
    var chinese: String
    var english: String?
}

struct WordForm: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case inflection
        case plural
        case pastTense
        case pastParticiple
        case presentParticiple
        case thirdPersonSingular
        case comparative
        case superlative
        case adverb
        case verb
    }

    var kind: Kind
    var value: String
}

struct DictionaryEntry: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var headword: String
    var normalizedKey: String
    var phonetic: String?
    var senses: [WordSense]
    var forms: [WordForm]
    var tags: [String]
    var frequencyRank: Int?
    var dictionaryVersion: String

    var primaryTranslation: String {
        senses.first?.chinese ?? ""
    }

    /// True when the entry carries authoritative dictionary content
    /// (definitions, pronunciation, forms, tags). System-dictionary lookups
    /// produce key-only entries that must never overwrite stored or
    /// user-supplied content.
    var isContentBearing: Bool {
        phonetic?.isEmpty == false
            || !senses.isEmpty
            || !forms.isEmpty
            || !tags.isEmpty
    }
}

struct DictionaryLookupResult: Hashable, Sendable {
    var originalInput: String
    var status: LookupStatus
    var entry: DictionaryEntry?
    var suggestions: [DictionaryEntry]

    init(
        originalInput: String,
        status: LookupStatus,
        entry: DictionaryEntry?,
        suggestions: [DictionaryEntry] = []
    ) {
        self.originalInput = originalInput
        self.status = status
        self.entry = entry
        self.suggestions = suggestions
    }
}

protocol DictionaryLookupService: Sendable {
    func lookup(_ rawInput: String) async throws -> DictionaryLookupResult
}
