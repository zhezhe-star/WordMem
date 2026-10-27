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
