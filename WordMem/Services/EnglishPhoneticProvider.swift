import Foundation

protocol EnglishPhoneticProviding: Sendable {
    func phonetic(for word: String) async -> String?
}

/// Offline IPA lookup backed by the CMU Pronouncing Dictionary. Missing words
/// stay missing: we never invent a phonetic transcription.
actor CMUDictionaryPhoneticProvider: EnglishPhoneticProviding {
    static let shared = CMUDictionaryPhoneticProvider()

    private var pronunciations: [String: String]?
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func phonetic(for word: String) async -> String? {
        if pronunciations == nil {
            pronunciations = Self.loadPronunciations(from: bundle)
        }
        guard let pronunciations, !word.isEmpty else { return nil }
        return pronunciations[Self.normalizationKey(word)]
    }

    private static func loadPronunciations(from bundle: Bundle) -> [String: String]? {
        guard let url = bundle.url(
            forResource: "cmudict-0.7b",
            withExtension: nil,
            subdirectory: nil
        ), let data = try? Data(contentsOf: url),
           let source = String(data: data, encoding: .isoLatin1) else {
            return nil
        }

        var results: [String: String] = [:]
        let normalizedSource = source.replacingOccurrences(of: "\r\n", with: "\n")
        for line in normalizedSource.split(separator: "\n", omittingEmptySubsequences: true) {
            guard !line.hasPrefix(";"), let spaceIndex = line.firstIndex(of: " ") else { continue }
            let rawWord = String(line[..<spaceIndex])
            let phonemes = line[line.index(after: spaceIndex)...]
                .split(separator: " ", omittingEmptySubsequences: true)
            guard !rawWord.isEmpty, !phonemes.isEmpty else { continue }

            let key = normalizationKey(rawWord)
            guard !key.isEmpty else { continue }
            guard results[key] == nil else { continue }
            results[key] = phonemes.compactMap(ipa).joined()
        }
        return results.isEmpty ? nil : results
    }

    static func normalizationKey(_ rawWord: String) -> String {
        var word = rawWord
        if let variantStart = word.firstIndex(of: "(") {
            word = String(word[..<variantStart])
        }
        return word.lowercased()
    }

    static func ipa(_ phoneme: Substring) -> String? {
        let base = phoneme.last.map(\.isNumber) == true
            ? phoneme.dropLast()
            : phoneme
        return switch base {
        case "AA": "ɑ"
        case "AE": "æ"
        case "AH": phoneme == "AH0" ? "ə" : "ʌ"
        case "AO": "ɔ"
        case "AW": "aʊ"
        case "AY": "aɪ"
        case "EH": "ɛ"
        case "ER": phoneme == "ER0" ? "ɚ" : "ɝ"
        case "EY": "eɪ"
        case "IH": "ɪ"
        case "IY": "i"
        case "OW": "oʊ"
        case "OY": "ɔɪ"
        case "UH": "ʊ"
        case "UW": "u"
        case "B": "b"
        case "CH": "tʃ"
        case "D": "d"
        case "DH": "ð"
        case "F": "f"
        case "G": "ɡ"
        case "HH": "h"
        case "JH": "dʒ"
        case "K": "k"
        case "L": "l"
        case "M": "m"
        case "N": "n"
        case "NG": "ŋ"
        case "P": "p"
        case "R": "r"
        case "S": "s"
        case "SH": "ʃ"
        case "T": "t"
        case "TH": "θ"
        case "V": "v"
        case "W": "w"
        case "Y": "j"
        case "Z": "z"
        case "ZH": "ʒ"
        default: nil
        }
    }
}
