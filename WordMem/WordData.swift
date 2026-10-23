import Foundation

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

    static func pickerChips(from source: String) -> [String] {
        var values: [String] = []
        let phrase = normalizedPhrase(from: source)
        if !phrase.isEmpty {
            values.append(phrase)
        }

        for word in wordChips(from: source) where !values.contains(word) {
            values.append(word)
        }
        return values
    }

    static func normalizedPhrase(from source: String) -> String {
        source
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
    }
}
