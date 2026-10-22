import Foundation

// MARK: - Calendar word adapter

/// Value-type snapshot of a wordbook entry consumed by the challenge engine.
/// Keeping this decoupled from SwiftData models makes scheduling and question
/// generation deterministic and unit-testable without a model container.
struct CalendarWord: Identifiable, Equatable {
    let id: UUID
    let word: String
    let translation: String
    let phonetic: String?
    let exampleSentence: String?
    let createdAt: Date
}

extension WordEntry {
    var calendarWord: CalendarWord {
        CalendarWord(
            id: id,
            word: headword,
            translation: displayTranslation,
            phonetic: phonetic,
            exampleSentence: legacyExampleSentence ?? legacyExample,
            createdAt: createdAt
        )
    }
}

// MARK: - Local Calendar Challenge models

enum CalendarChallengeForm: String, Codable, CaseIterable {
    case meaningChoice
    case listeningChoice
    case reverseTranslation
    case exampleCloze
    case spellingInput
}

struct CalendarChallengeQuestion: Identifiable, Codable, Equatable {
    let id: String
    let wordID: UUID
    let form: CalendarChallengeForm
    /// The word being tested. The full-page card renders this as the visual
    /// hero, so it is carried explicitly instead of parsed out of `prompt`.
    let target: String
    /// The word's display translation, carried so reverse-prompt cards can
    /// render it as the hero without parsing `prompt`.
    let targetTranslation: String
    let prompt: String
    let accessibilityPrompt: String
    let exampleText: String?
    let options: [String]
    let answer: String
    let hint: String?
}

struct CalendarChallengeAnswer: Codable, Equatable {
    var wordID: UUID
    var form: CalendarChallengeForm
    var response: String
    var isCorrect: Bool
    var wasRevealed: Bool
    var answeredAt: Date
}

struct CalendarChallengeDayProgress: Codable, Equatable {
    var answers: [String: CalendarChallengeAnswer]
    var completedAt: Date?
}

struct CalendarChallengeProgress: Codable, Equatable {
    var schemaVersion: Int = 1
    var days: [String: CalendarChallengeDayProgress]

    init(days: [String: CalendarChallengeDayProgress] = [:]) {
        self.schemaVersion = 1
        self.days = days
    }
}

// MARK: - Day status

enum CalendarChallengeDayStatus: Equatable {
    case empty
    case rest
    case future
    case due
    case partial
    case complete
}

// MARK: - Injectable challenge service

final class CalendarChallengeService: ObservableObject {
    static let scheduleOffsetsInDays = [0, 1, 3, 7, 14]
    private static let storageKey = "wordmem.calendar_challenge.progress.v1"

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let clock: () -> Date

    @Published private(set) var progress: CalendarChallengeProgress

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        clock: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.clock = clock
        self.progress = Self.loadProgress(from: defaults)
    }

    // MARK: Persistence

    private static func loadProgress(from defaults: UserDefaults) -> CalendarChallengeProgress {
        guard let data = defaults.data(forKey: storageKey) else {
            return CalendarChallengeProgress()
        }

        do {
            let progress = try JSONDecoder().decode(CalendarChallengeProgress.self, from: data)
            return progress.schemaVersion == 1 ? progress : CalendarChallengeProgress()
        } catch {
            // Challenge data is intentionally isolated from saved_words. A malformed
            // payload recovers to an empty schedule instead of breaking the wordbook.
            return CalendarChallengeProgress()
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(progress)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            // Persistence failures must not mutate the wordbook. Keeping the in-memory
            // progress lets the user continue until the app process ends.
        }
    }

    func currentDate() -> Date {
        clock()
    }

    // MARK: Deterministic local days and due scheduling

    func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    func dayOffset(from startDate: Date, to date: Date) -> Int? {
        let start = startOfDay(for: startDate)
        let target = startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: target).day
    }

    func dueWords(on date: Date, from words: [CalendarWord]) -> [CalendarWord] {
        let day = startOfDay(for: date)
        return words
            .compactMap { word -> (CalendarWord, Int)? in
                guard let offset = dayOffset(from: word.createdAt, to: day), offset >= 0 else {
                    return nil
                }
                return Self.scheduleOffsetsInDays.contains(offset) ? (word, offset) : nil
            }
            .sorted { lhs, rhs in
                if lhs.0.word.caseInsensitiveCompare(rhs.0.word) != .orderedSame {
                    return lhs.0.word.localizedCaseInsensitiveCompare(rhs.0.word) == .orderedAscending
                }
                return lhs.0.id.uuidString < rhs.0.id.uuidString
            }
            .map(\.0)
    }

    func dayStatus(on date: Date, from words: [CalendarWord], relativeTo now: Date? = nil) -> CalendarChallengeDayStatus {
        let dueWords = dueWords(on: date, from: words)
        if dueWords.isEmpty {
            return words.isEmpty ? .empty : .rest
        }

        if startOfDay(for: date) > startOfDay(for: now ?? clock()) {
            return .future
        }

        let answeredCount = answeredCount(on: date, expectedWords: dueWords)
        if answeredCount == 0 {
            return .due
        }
        return answeredCount < dueWords.count ? .partial : .complete
    }

    // MARK: Answer and completion transitions

    func questions(on date: Date, from words: [CalendarWord]) -> [CalendarChallengeQuestion] {
        let dueWords = dueWords(on: date, from: words)
        let dayIdentifier = dayKey(for: date)
        let otherWords = words.sorted {
            if $0.word.caseInsensitiveCompare($1.word) != .orderedSame {
                return $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }

        return dueWords.enumerated().map { index, word in
            Self.makeQuestion(
                for: word,
                index: index,
                allWords: otherWords,
                dayKey: dayIdentifier
            )
        }
    }

    func answer(for question: CalendarChallengeQuestion, on date: Date) -> CalendarChallengeAnswer? {
        progress.days[dayKey(for: date)]?.answers[question.id]
    }

    func answeredCount(on date: Date, expectedWords: [CalendarWord]) -> Int {
        let dayProgress = progress.days[dayKey(for: date)]
        let expectedIDs = Set(expectedWords.map(\.id))
        let answers = dayProgress?.answers.values.filter { expectedIDs.contains($0.wordID) } ?? []
        return Set(answers.map(\.wordID)).count
    }

    func recordAnswer(
        _ answer: CalendarChallengeAnswer,
        for question: CalendarChallengeQuestion,
        on date: Date,
        expectedWords: [CalendarWord]
    ) {
        let key = dayKey(for: date)
        var dayProgress = progress.days[key] ?? CalendarChallengeDayProgress(answers: [:], completedAt: nil)
        dayProgress.answers[question.id] = answer

        let expectedIDs = Set(expectedWords.map(\.id))
        let answeredIDs = Set(dayProgress.answers.values.map(\.wordID))
        if !expectedIDs.isEmpty && expectedIDs.subtracting(answeredIDs).isEmpty {
            dayProgress.completedAt = answer.answeredAt
        }

        progress.days[key] = dayProgress
        persist()
    }

    // MARK: Pure question generation

    static func makeQuestion(
        for word: CalendarWord,
        index: Int,
        allWords: [CalendarWord],
        dayKey: String
    ) -> CalendarChallengeQuestion {
        var availableForms: [CalendarChallengeForm] = [
            .meaningChoice,
            .listeningChoice,
            .reverseTranslation,
            .spellingInput,
        ]

        let example = word.exampleSentence.flatMap { $0.isEmpty ? nil : $0 }
        if let example = example, example.localizedCaseInsensitiveContains(word.word) {
            availableForms.insert(.exampleCloze, at: min(3, availableForms.count))
        }

        let rotation = Int(stableSeed(seedFor: word.id.uuidString) % UInt64(availableForms.count))
        let rotatedForms = Array(availableForms[rotation...] + availableForms[..<rotation])
        let form = rotatedForms[index % rotatedForms.count]
        let distractors = distractorTranslationsAndWords(for: word, allWords: allWords, form: form)

        switch form {
        case .meaningChoice:
            return CalendarChallengeQuestion(
                id: questionID(dayKey: dayKey, word: word, form: form),
                wordID: word.id,
                form: form,
                target: word.word,
                targetTranslation: word.translation,
                prompt: "选择「\(word.word)」的正确释义",
                accessibilityPrompt: "请选择单词 \(word.word) 的正确释义。",
                exampleText: nil,
                options: options(answer: word.translation, distractors: distractors.translations, seed: stableSeed(seedFor: word.id.uuidString + form.rawValue)),
                answer: word.translation,
                hint: word.phonetic
            )

        case .listeningChoice:
            return CalendarChallengeQuestion(
                id: questionID(dayKey: dayKey, word: word, form: form),
                wordID: word.id,
                form: form,
                target: word.word,
                targetTranslation: word.translation,
                prompt: "听发音，选择正确单词",
                accessibilityPrompt: "这是听力选择题。播放发音后，请选择正确的单词。",
                exampleText: nil,
                options: options(answer: word.word, distractors: distractors.words, seed: stableSeed(seedFor: word.id.uuidString + form.rawValue)),
                answer: word.word,
                hint: word.phonetic
            )

        case .reverseTranslation:
            return CalendarChallengeQuestion(
                id: questionID(dayKey: dayKey, word: word, form: form),
                wordID: word.id,
                form: form,
                target: word.word,
                targetTranslation: word.translation,
                prompt: "选择「\(word.translation)」对应的英文",
                accessibilityPrompt: "请选择释义 \(word.translation) 对应的英文单词。",
                exampleText: nil,
                options: options(answer: word.word, distractors: distractors.words, seed: stableSeed(seedFor: word.id.uuidString + form.rawValue)),
                answer: word.word,
                hint: word.phonetic
            )

        case .exampleCloze:
            let sentence = example ?? ""
            let cloze = sentence.replacingOccurrences(
                of: word.word,
                with: "______",
                options: .caseInsensitive,
                range: sentence.range(of: word.word, options: .caseInsensitive)
            )
            return CalendarChallengeQuestion(
                id: questionID(dayKey: dayKey, word: word, form: form),
                wordID: word.id,
                form: form,
                target: word.word,
                targetTranslation: word.translation,
                prompt: "根据语境补全例句",
                accessibilityPrompt: "请根据语境，选择补充到例句中的单词。",
                exampleText: cloze,
                options: options(answer: word.word, distractors: distractors.words, seed: stableSeed(seedFor: word.id.uuidString + form.rawValue)),
                answer: word.word,
                hint: word.phonetic
            )

        case .spellingInput:
            return CalendarChallengeQuestion(
                id: questionID(dayKey: dayKey, word: word, form: form),
                wordID: word.id,
                form: form,
                target: word.word,
                targetTranslation: word.translation,
                prompt: "拼写「\(word.translation)」",
                accessibilityPrompt: "请拼写出释义 \(word.translation) 对应的英文单词。",
                exampleText: example,
                options: [],
                answer: word.word,
                hint: word.phonetic
            )
        }
    }

    private static func questionID(dayKey: String, word: CalendarWord, form: CalendarChallengeForm) -> String {
        "\(dayKey):\(word.id.uuidString):\(form.rawValue)"
    }

    private static func stableSeed(seedFor value: String) -> UInt64 {
        var seed: UInt64 = 1_469_598_103_934_665_603
        for byte in value.utf8 {
            seed ^= UInt64(byte)
            seed = seed &* 1_099_511_628_211
        }
        return seed
    }

    private static func distractorTranslationsAndWords(
        for word: CalendarWord,
        allWords: [CalendarWord],
        form: CalendarChallengeForm
    ) -> (translations: [String], words: [String]) {
        let otherWords = allWords.filter { $0.id != word.id }
        let seed = stableSeed(seedFor: word.id.uuidString + form.rawValue)

        var translations = uniqueValues(
            otherWords.compactMap(\.translation).filter { $0 != word.translation }
        )
        var words = uniqueValues(
            otherWords.map(\.word).filter { $0.caseInsensitiveCompare(word.word) != .orderedSame }
        )

        translations = translations.sorted { stableSeed(seedFor: $0 + String(seed)) < stableSeed(seedFor: $1 + String(seed)) }
        words = words.sorted { stableSeed(seedFor: $0 + String(seed)) < stableSeed(seedFor: $1 + String(seed)) }

        return (Array(translations.prefix(3)), Array(words.prefix(3)))
    }

    private static func options(answer: String, distractors: [String], seed: UInt64) -> [String] {
        return uniqueValues([answer] + distractors).sorted {
            stableSeed(seedFor: $0 + String(seed)) < stableSeed(seedFor: $1 + String(seed))
        }
    }

    private static func uniqueValues(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            let key = value.lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { return false }
            return true
        }
    }
}
