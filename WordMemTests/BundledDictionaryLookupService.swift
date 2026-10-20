@testable import WordMem
import Foundation

actor BundledDictionaryLookupService: DictionaryLookupService {
    private let entriesByID: [String: DictionaryEntry]
    private let entriesByKey: [String: DictionaryEntry]
    private let lemmaByKey: [String: String]
    private let dictionaryVersion: String

    init(catalog: [DictionaryEntry]) {
        var entriesByID: [String: DictionaryEntry] = [:]
        var entriesByKey: [String: DictionaryEntry] = [:]
        for entry in catalog {
            entriesByID[entry.id] = entry
            entriesByKey[entry.normalizedKey] = entry
        }

        self.entriesByID = entriesByID
        self.entriesByKey = entriesByKey
        dictionaryVersion = DevelopmentSeedDictionaryCatalog.version

        var lemmaIndex: [String: String] = [:]
        for entry in catalog {
            lemmaIndex[entry.normalizedKey] = entry.normalizedKey
            for form in entry.forms {
                let formKey = WordInputNormalizer.normalizedKey(from: form.value)
                lemmaIndex[formKey] = entry.normalizedKey
            }
        }
        lemmaByKey = lemmaIndex
    }

    func lookup(_ rawInput: String) async throws -> DictionaryLookupResult {
        let key = WordInputNormalizer.normalizedKey(from: rawInput)
        guard !key.isEmpty else {
            return DictionaryLookupResult(originalInput: rawInput, status: .notFound, entry: nil)
        }

        if let entry = entriesByKey[key] {
            return DictionaryLookupResult(originalInput: rawInput, status: .enriched, entry: entry)
        }

        if let lemmaKey = lemmaByKey[key], let lemma = entriesByKey[lemmaKey] {
            return DictionaryLookupResult(originalInput: rawInput, status: .lemmaResolved, entry: lemma)
        }

        let generatedEntry = DictionaryEntry(
            id: "user:\(key)",
            headword: rawInput.trimmingCharacters(in: .whitespacesAndNewlines),
            normalizedKey: key,
            phonetic: nil,
            senses: [],
            forms: [],
            tags: [],
            frequencyRank: nil,
            dictionaryVersion: dictionaryVersion
        )

        let candidates = closestEntries(to: key, limit: 5)
        if let best = candidates.first, isHighConfidenceCorrection(input: key, candidate: best.normalizedKey) {
            return DictionaryLookupResult(originalInput: rawInput, status: .autoCorrected, entry: best)
        }

        return DictionaryLookupResult(
            originalInput: rawInput,
            status: .notFound,
            entry: generatedEntry,
            suggestions: candidates
        )
    }

    private func closestEntries(to key: String, limit: Int) -> [DictionaryEntry] {
        entriesByKey.values
            .map { (entry: $0, distance: levenshteinDistance(key, $0.normalizedKey)) }
            .filter { $0.distance > 0 }
            .sorted {
                if $0.distance != $1.distance { return $0.distance < $1.distance }
                return ($0.entry.frequencyRank ?? .max) < ($1.entry.frequencyRank ?? .max)
            }
            .prefix(limit)
            .map(\.entry)
    }

    private func isHighConfidenceCorrection(input: String, candidate: String) -> Bool {
        let distance = levenshteinDistance(input, candidate)
        let allowedDistance = input.count < 4 ? 0 : input.count < 7 ? 1 : 2
        return distance > 0 && distance <= allowedDistance
    }

    private func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }

        var previous = Array(0...right.count)
        var current = [Int](repeating: 0, count: right.count + 1)

        for leftIndex in 1...left.count {
            current[0] = leftIndex
            for rightIndex in 1...right.count {
                let substitutionCost = left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1
                current[rightIndex] = min(
                    previous[rightIndex] + 1,
                    current[rightIndex - 1] + 1,
                    previous[rightIndex - 1] + substitutionCost
                )
            }
            swap(&previous, &current)
        }

        return previous[right.count]
    }
}
