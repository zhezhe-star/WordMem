import Foundation

struct WordIdentity: Equatable, Hashable, Sendable {
    static let defaultLocaleIdentifier = "en_US_POSIX"

    let locale: Locale
    let key: String

    init(locale: Locale = Locale(identifier: WordIdentity.defaultLocaleIdentifier), key: String) {
        self.locale = locale
        self.key = key
    }
}

/// Public seam over the only dictionary source allowed in WordMem: Apple's
/// system dictionary availability check. It never returns dictionary content.
protocol SystemDictionaryAuthorizing: Sendable {
    func hasDefinition(forTerm term: String) async -> Bool
}
