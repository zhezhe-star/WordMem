import Foundation

enum WordInputNormalizer {
    static func normalizedKey(from rawInput: String) -> String {
        let replaced = rawInput
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = replaced.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: WordIdentity.defaultLocaleIdentifier)
        )
        return folded.trimmingCharacters(in: .punctuationCharacters).lowercased()
    }
}
