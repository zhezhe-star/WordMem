import Foundation
import NaturalLanguage
import UIKit

/// A target-independent representation of one selectable source token.
struct ImportCandidateChip: Identifiable, Hashable, Sendable {
    let id: String
    let text: String
    let detail: String?
    let sourceOrder: Int
    let group: String?
    let advice: ImportWordAdvice?

    init(
        id: String,
        text: String,
        detail: String? = nil,
        sourceOrder: Int,
        group: String? = nil,
        advice: ImportWordAdvice? = nil
    ) {
        self.id = id
        self.text = text
        self.detail = detail
        self.sourceOrder = sourceOrder
        self.group = group
        self.advice = advice
    }

    /// Both the corrected key and a restored original key must be present in
    /// the system dictionary before the candidate can enter a submission.
    var isImportable: Bool {
        guard let advice else { return true }
        if advice.isOriginalRestored {
            return advice.isOriginalDictionaryAvailable
        }
        return advice.isDictionaryAvailable
    }

    var canRestoreOriginal: Bool {
        advice?.canRestoreOriginal == true
    }

    func restoringOriginal() -> ImportCandidateChip {
        guard let advice, advice.canRestoreOriginal else { return self }
        let restoredAdvice = ImportWordAdvice(
            originalText: advice.originalText,
            originalKey: advice.originalKey,
            context: advice.context,
            lemma: advice.lemma,
            spellingCorrection: advice.spellingCorrection,
            finalText: advice.originalText,
            finalKey: advice.originalKey,
            isDictionaryAvailable: advice.isOriginalDictionaryAvailable,
            isOriginalDictionaryAvailable: advice.isOriginalDictionaryAvailable,
            isOriginalRestored: true
        )
        return ImportCandidateChip(
            id: advice.originalKey,
            text: advice.originalText,
            detail: detail,
            sourceOrder: sourceOrder,
            group: group,
            advice: restoredAdvice
        )
    }

    var lemmaBadgeText: String? {
        guard let advice, advice.isLemmaNormalized else { return nil }
        return "原形 \(advice.finalText)"
    }

    var spellingBadgeText: String? {
        guard let advice, advice.isSpellingCorrected else { return nil }
        return "拼写纠正 \(advice.originalText) → \(advice.finalText)"
    }

    var availabilityBadgeText: String? {
        guard let advice, !advice.isDictionaryAvailable else { return nil }
        return "词典不可用"
    }
}

/// Immutable provenance for one advised import candidate. Keeping the source
/// value here lets a corrected word still be restored without losing context.
struct ImportWordAdvice: Equatable, Hashable, Sendable {
    let originalText: String
    let originalKey: String
    let context: String?
    let lemma: String?
    let spellingCorrection: String?
    let finalText: String
    let finalKey: String
    let isDictionaryAvailable: Bool
    let isOriginalDictionaryAvailable: Bool
    var isOriginalRestored = false

    var canRestoreOriginal: Bool {
        !isOriginalRestored && isOriginalDictionaryAvailable
    }

    var isLemmaNormalized: Bool {
        WordInputNormalizer.normalizedKey(from: finalText)
            .replacingOccurrences(of: "'", with: "") != originalKey
    }

    var isSpellingCorrected: Bool {
        guard let spellingCorrection else { return false }
        return spellingCorrection.compare(
            originalText,
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        ) != .orderedSame
    }
}

protocol ImportWordLemmaProviding: Sendable {
    func lemma(for word: String, context: String?) async -> String?
}

protocol ImportWordSpellingSuggesting: Sendable {
    func correction(for word: String) async -> String?
}

typealias ImportWordAvailabilityChecking = AuthoritativeDictionaryAuthorizing

/// Shared async advisor used by every sentence-splitting import surface.
struct ImportWordAdvisor: Sendable {
    private let lemmaProvider: any ImportWordLemmaProviding
    private let spellingSuggester: any ImportWordSpellingSuggesting
    private let availability: any ImportWordAvailabilityChecking

    init(
        lemmaProvider: any ImportWordLemmaProviding,
        spellingSuggester: any ImportWordSpellingSuggesting,
        availability: any ImportWordAvailabilityChecking
    ) {
        self.lemmaProvider = lemmaProvider
        self.spellingSuggester = spellingSuggester
        self.availability = availability
    }

    static func live() -> ImportWordAdvisor {
        ImportWordAdvisor(
            lemmaProvider: NaturalLanguageWordLemmaProvider(),
            spellingSuggester: UITextCheckerSpellingSuggester(),
            availability: WordNetKitAuthoritativeDictionaryProvider.shared
        )
    }

    func chips(
        from candidates: [WordImportCandidate],
        context: String? = nil
    ) async -> [ImportCandidateChip] {
        var advisedChips: [ImportCandidateChip] = []
        var seenFinalKeys = Set<String>()

        for (offset, candidate) in candidates.enumerated() {
            let originalKey = WordInputNormalizer.normalizedKey(from: candidate.text)
                .replacingOccurrences(of: "'", with: "")
            guard !originalKey.isEmpty else { continue }

            let correction = await spellingSuggester.correction(for: candidate.text)
            let lemmaSource = correction ?? candidate.text
            let lemma = await lemmaProvider.lemma(for: lemmaSource, context: context)
            let finalText = lemma ?? lemmaSource
            let finalKey = WordInputNormalizer.normalizedKey(from: finalText)
                .replacingOccurrences(of: "'", with: "")
            guard !finalKey.isEmpty, seenFinalKeys.insert(finalKey).inserted else { continue }

            let isAvailable = await availability.hasDefinition(forTerm: finalKey)
            let isOriginalAvailable = finalKey == originalKey
                ? isAvailable
                : await availability.hasDefinition(forTerm: originalKey)
            let advice = ImportWordAdvice(
                originalText: candidate.text,
                originalKey: originalKey,
                context: context,
                lemma: lemma,
                spellingCorrection: correction,
                finalText: finalText,
                finalKey: finalKey,
                isDictionaryAvailable: isAvailable,
                isOriginalDictionaryAvailable: isOriginalAvailable
            )
            advisedChips.append(
                ImportCandidateChip(
                    id: finalKey,
                    text: finalText,
                    sourceOrder: offset,
                    advice: advice
                )
            )
        }

        return advisedChips
    }
}

/// Public NaturalLanguage lemma lookup, anchored to the original sentence when
/// one is supplied so ambiguous forms retain their context.
struct NaturalLanguageWordLemmaProvider: ImportWordLemmaProviding {
    func lemma(for word: String, context: String?) async -> String? {
        let text = context?.isEmpty == false ? context! : word
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        tagger.setLanguage(.english, range: text.startIndex..<text.endIndex)

        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        var result: NLTag?
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lemma,
            options: options
        ) { tag, tokenRange in
            let token = String(text[tokenRange])
            if token.localizedCaseInsensitiveCompare(word) == .orderedSame, let tag {
                result = tag
                return false
            }
            return true
        }
        return result?.rawValue.lowercased()
    }
}

/// UITextChecker is the public system spelling source. A suggestion is only
/// used when the source word is actually reported misspelled.
struct UITextCheckerSpellingSuggester: ImportWordSpellingSuggesting {
    func correction(for word: String) async -> String? {
        await MainActor.run {
            let checker = UITextChecker()
            let range = NSRange(word.startIndex..., in: word)
            let misspelledRange = checker.rangeOfMisspelledWord(
                in: word,
                range: range,
                startingAt: range.location,
                wrap: false,
                language: "en_US"
            )
            guard misspelledRange.location != NSNotFound else { return nil }
            return checker.guesses(
                forWordRange: misspelledRange,
                in: word,
                language: "en_US"
            )?.first
        }
    }
}

/// Small façade so sentence and translation-provider callers produce the same
/// chip model without duplicating advisor behavior.
enum ImportCandidatePipeline {
    static func chips(
        from candidates: [WordImportCandidate],
        context: String?,
        advisor: ImportWordAdvisor = .live()
    ) async -> [ImportCandidateChip] {
        await advisor.chips(from: candidates, context: context)
    }

    static func translationChips(
        from source: String,
        advisor: ImportWordAdvisor = .live()
    ) async -> [ImportCandidateChip] {
        let phrase = TranslationWordTokenizer.normalizedPhrase(from: source)
        var chips: [ImportCandidateChip] = []
        if !phrase.isEmpty {
            // Phrase context intentionally bypasses the word-level dictionary
            // gate; the advisor applies only to individual word candidates.
            chips.append(
                ImportCandidateChip(
                    id: phrase,
                    text: phrase,
                    sourceOrder: 0,
                    group: "整句"
                )
            )
        }

        let candidates = EnglishWordCandidateSplitter.candidates(from: source)
        let advisedWords = await advisor.chips(from: candidates, context: source)
        chips.append(
            contentsOf: advisedWords.map {
                ImportCandidateChip(
                    id: $0.id,
                    text: $0.text,
                    sourceOrder: $0.sourceOrder + 1,
                    group: "单词",
                    advice: $0.advice
                )
            }
        )
        return ImportCandidateChip.uniquelyIdentified(chips)
    }
}

struct WordImportCandidate: Identifiable, Hashable {
    var text: String
    var normalizedKey: String

    var id: String { normalizedKey }
}

/// Converts advisor-covered selected chips back into the single submission
/// format. Metadata is the non-migrating provenance channel shared by every
/// import source.
extension ImportCandidatePipeline {
    static func payload(from chip: ImportCandidateChip) -> WordImportCandidatePayload {
        var metadata: [String: String] = ["sourceOrder": String(chip.sourceOrder)]
        if let advice = chip.advice {
            metadata["originalWord"] = advice.originalText
            metadata["originalKey"] = advice.originalKey
            if let context = advice.context, !context.isEmpty {
                metadata["sourceContext"] = context
            }
            if advice.isSpellingCorrected, let correction = advice.spellingCorrection, !correction.isEmpty {
                metadata["spellingCorrection"] = correction
            }
            if advice.isLemmaNormalized, let lemma = advice.lemma, !lemma.isEmpty {
                metadata["lemma"] = lemma
            }
            if advice.isOriginalRestored {
                metadata["originalSpellingRestored"] = "true"
            }
        } else if chip.group == "整句" {
            metadata["phraseContext"] = "true"
        }

        return WordImportCandidatePayload(
            text: chip.text,
            normalizedKey: chip.id,
            metadata: metadata
        )
    }

    static func payloads(from chips: [ImportCandidateChip]) -> [WordImportCandidatePayload] {
        chips.map(payload(from:))
    }
}

enum ImportCandidateAdapter {
    /// Preserves the app candidate's normalized identity and source order.
    static func chips(from candidates: [WordImportCandidate]) -> [ImportCandidateChip] {
        candidates.enumerated().map { offset, candidate in
            ImportCandidateChip(
                id: candidate.normalizedKey,
                text: candidate.text,
                sourceOrder: offset
            )
        }
    }
}

enum EnglishWordCandidateSplitter {
    private static let expression = try! NSRegularExpression(
        pattern: #"[A-Za-z]+(?:['’][A-Za-z]+|-[A-Za-z]+)*"#,
        options: []
    )

    static func candidates(from sourceText: String) -> [WordImportCandidate] {
        var candidates: [WordImportCandidate] = []
        var seenKeys = Set<String>()

        let range = NSRange(sourceText.startIndex..., in: sourceText)
        for match in expression.matches(in: sourceText, range: range) {
            guard let matchRange = Range(match.range, in: sourceText) else { continue }
            let text = String(sourceText[matchRange])
            // Contraction apostrophes are spelling details; candidate identity uses the bare word.
            let key = WordInputNormalizer.normalizedKey(from: text)
                .replacingOccurrences(of: "'", with: "")
            guard !key.isEmpty, seenKeys.insert(key).inserted else { continue }
            candidates.append(
                WordImportCandidate(text: text, normalizedKey: key)
            )
        }

        return candidates
    }
}


extension ImportCandidateChip {
    /// Keeps the first appearance of every identity so reusable views cannot
    /// crash on duplicate IDs and stable source order remains predictable.
    static func uniquelyIdentified(_ chips: [ImportCandidateChip]) -> [ImportCandidateChip] {
        var seenIDs = Set<String>()
        return chips.filter { seenIDs.insert($0.id).inserted }
    }
}

enum ImportCandidateAccessibility {
    static func label(text: String, meaning: String?) -> String {
        let trimmedMeaning = meaning?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedMeaning.isEmpty ? text : "\(text)，\(trimmedMeaning)"
    }
}

/// `Text` has no public wrapped-line count, so long unwrapped paragraphs use a
/// conservative character threshold in addition to explicit line breaks.
struct ImportContextExpansion: Equatable {
    let isExpandable: Bool
    private(set) var isExpanded = false

    init(text: String, collapsedLineLimit: Int = 5, wrappedCharacterLimit: Int = 220) {
        let lineCount = text.components(separatedBy: .newlines).count
        isExpandable = lineCount > collapsedLineLimit || text.count > wrappedCharacterLimit
    }

    var lineLimit: Int? {
        isExpandable && !isExpanded ? 5 : nil
    }

    mutating func toggle() {
        guard isExpandable else { return }
        isExpanded.toggle()
    }
}

struct ImportCandidateSection: Identifiable, Hashable, Sendable {
    let title: String?
    let chips: [ImportCandidateChip]

    var id: String { title ?? "" }
}

enum ImportCandidateOrganizer {
    /// Preserves original reading order and groups only when a caller supplies
    /// group metadata, so 50+ chips stay predictable without list rebuilds.
    static func sections(from chips: [ImportCandidateChip]) -> [ImportCandidateSection] {
        let orderedChips = chips.sorted { $0.sourceOrder < $1.sourceOrder }
        var groupedChips: [String: [ImportCandidateChip]] = [:]
        var groupOrder: [String] = []

        for chip in orderedChips {
            let group = chip.group ?? "全部"
            if groupedChips[group] == nil {
                groupOrder.append(group)
            }
            groupedChips[group, default: []].append(chip)
        }

        return groupOrder.map { title in
            ImportCandidateSection(
                title: groupOrder.count == 1 && title == "全部" ? nil : title,
                chips: groupedChips[title] ?? []
            )
        }
    }
}

/// Stores explicit user selections. Candidates never start selected, and
/// selected results always follow `chips` source order.
struct ImportChipSelection: Equatable, Sendable {
    private var orderedIDs: [String]
    private var chipsByID: [String: ImportCandidateChip]
    private var selectedIDs: Set<String>

    init(chips: [ImportCandidateChip]) {
        let uniqueChips = ImportCandidateChip.uniquelyIdentified(chips)
        orderedIDs = uniqueChips.map(\.id)
        chipsByID = Dictionary(uniqueKeysWithValues: uniqueChips.map { ($0.id, $0) })
        selectedIDs = []
    }

    var selectedCount: Int { selectedIDs.count }

    var selectedChips: [ImportCandidateChip] {
        orderedIDs.compactMap { id in
            selectedIDs.contains(id) ? chipsByID[id] : nil
        }
    }

    func isSelected(_ id: String) -> Bool {
        selectedIDs.contains(id)
    }

    mutating func select(_ id: String) {
        guard chipsByID[id]?.isImportable == true else { return }
        selectedIDs.insert(id)
    }

    mutating func deselect(_ id: String) {
        selectedIDs.remove(id)
    }

    mutating func toggle(_ id: String) {
        if isSelected(id) {
            deselect(id)
        } else {
            select(id)
        }
    }

    mutating func selectAll() {
        selectedIDs = Set(orderedIDs.filter { chipsByID[$0]?.isImportable == true })
    }

    mutating func clear() {
        selectedIDs = []
    }

    mutating func updateChips(_ chips: [ImportCandidateChip]) {
        let uniqueChips = ImportCandidateChip.uniquelyIdentified(chips)
        orderedIDs = uniqueChips.map(\.id)
        chipsByID = Dictionary(uniqueKeysWithValues: uniqueChips.map { ($0.id, $0) })
        selectedIDs = selectedIDs.intersection(orderedIDs)
    }

}
