import Foundation

struct AuthoritativePronunciation: Equatable, Hashable, Sendable {
    let ipa: String
    let variety: String?
}

struct AuthoritativeDictionarySense: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let partOfSpeech: String
    let definition: String
    let examples: [String]
}

struct AuthoritativeDictionaryEntry: Equatable, Hashable, Sendable {
    let providerID: String
    let providerRevision: String
    let license: String
    let canonicalKey: String
    let headword: String
    let pronunciations: [AuthoritativePronunciation]
    let senses: [AuthoritativeDictionarySense]

    var primaryDefinition: String? {
        senses.first?.definition
    }

    var primaryPartOfSpeech: String? {
        senses.first?.partOfSpeech
    }

    var primaryIPA: String? {
        pronunciations.first?.ipa
    }
}

/// The only dictionary seam used for import authorization and inline content.
/// Implementations provide third-party dictionary content; they never define
/// WordMem's word identity.
protocol AuthoritativeDictionaryAuthorizing: Sendable {
    func hasDefinition(forTerm term: String) async -> Bool
    func entry(forTerm term: String) async throws -> AuthoritativeDictionaryEntry?
}
