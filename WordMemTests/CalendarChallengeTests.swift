import XCTest
@testable import WordMem

final class CalendarChallengeTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 9) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    private func makeWord(
        _ text: String,
        translation: String,
        createdAt: Date,
        example: String? = nil,
        id: UUID = UUID()
    ) -> CalendarWord {
        CalendarWord(
            id: id,
            word: text,
            translation: translation,
            phonetic: nil,
            exampleSentence: example,
            createdAt: createdAt
        )
    }

    private func makeService(
        suiteName: String = UUID().uuidString,
        now: @escaping () -> Date = Date.init
    ) -> (service: CalendarChallengeService, defaults: UserDefaults) {
        let defaults = UserDefaults(suiteName: suiteName)!
        let service = CalendarChallengeService(defaults: defaults, calendar: calendar, clock: now)
        return (service, defaults)
    }

    func testDayKeyUsesInjectedAsiaCalendarAndDayBoundary() {
        let (service, _) = makeService()
        let evening = makeDate(year: 2026, month: 10, day: 20, hour: 23)
        let nextMorning = makeDate(year: 2026, month: 10, day: 21, hour: 1)

        XCTAssertEqual(service.dayKey(for: evening), "2026-10-20")
        XCTAssertEqual(service.dayKey(for: nextMorning), "2026-10-21")
        XCTAssertEqual(
            service.startOfDay(for: evening),
            service.startOfDay(for: makeDate(year: 2026, month: 10, day: 20, hour: 1))
        )
    }

    func testDueSelectionIncludesScheduledPastDaysAndExcludesFutureWork() {
        let (service, _) = makeService()
        let base = makeDate(year: 2026, month: 10, day: 20)
        let words = [
            makeWord("apple", translation: "苹果", createdAt: base),
            makeWord("banana", translation: "香蕉", createdAt: base),
        ]

        XCTAssertEqual(Set(service.dueWords(on: base, from: words).map(\.word)), ["apple", "banana"])
        XCTAssertEqual(Set(service.dueWords(on: makeDate(year: 2026, month: 10, day: 21), from: words).map(\.word)), ["apple", "banana"])
        XCTAssertEqual(service.dueWords(on: makeDate(year: 2026, month: 10, day: 22), from: words).count, 0)
        XCTAssertEqual(service.dueWords(on: makeDate(year: 2026, month: 10, day: 23), from: words).count, 2)
        XCTAssertEqual(service.dueWords(on: makeDate(year: 2026, month: 11, day: 3), from: words).count, 2)

        let futureDay = makeDate(year: 2026, month: 10, day: 21)
        let fixedService = makeService(now: { base }).service
        XCTAssertEqual(fixedService.currentDate(), base)
        XCTAssertEqual(service.dayStatus(on: futureDay, from: words, relativeTo: base), .future)
        XCTAssertEqual(service.dayStatus(on: makeDate(year: 2026, month: 10, day: 22), from: words, relativeTo: base), .rest)
        XCTAssertEqual(service.dayStatus(on: base, from: [], relativeTo: base), .empty)
    }

    func testQuestionGenerationIsMixedStableAndUsesAvailableContent() {
        let (service, _) = makeService()
        let base = makeDate(year: 2026, month: 10, day: 20)
        let words = [
            makeWord(
                "apple",
                translation: "苹果",
                createdAt: base,
                example: "I eat an apple.",
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
            ),
            makeWord(
                "banana",
                translation: "香蕉",
                createdAt: base,
                example: "A banana is yellow.",
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
            ),
            makeWord(
                "cat",
                translation: "猫",
                createdAt: base,
                example: "The cat sleeps.",
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!
            ),
            makeWord(
                "dog",
                translation: "狗",
                createdAt: base,
                example: "The dog runs.",
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!
            ),
            makeWord(
                "egg",
                translation: "鸡蛋",
                createdAt: base,
                example: "I boiled an egg.",
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!
            ),
        ]

        let questions = service.questions(on: base, from: words)
        XCTAssertEqual(questions.count, 5)
        XCTAssertEqual(Set(questions.map(\.wordID)), Set(words.map(\.id)))
        XCTAssertEqual(
            Set(questions.map(\.form)).count >= 3,
            true,
            "\(questions.map { ($0.target, $0.form, $0.exampleText ?? "nil") })"
        )

        let repeatedQuestions = service.questions(on: base, from: words)
        XCTAssertEqual(questions, repeatedQuestions)
        XCTAssertTrue(questions.allSatisfy { !$0.prompt.isEmpty && !$0.answer.isEmpty })
    }

    func testAnswerPersistenceSurvivesServiceReloadAndIsolatesSavedWords() throws {
        let suiteName = "CalendarChallengeTests.\(UUID().uuidString)"
        let (service, defaults) = makeService(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let base = makeDate(year: 2026, month: 10, day: 20)
        let words = [
            makeWord("apple", translation: "苹果", createdAt: base),
            makeWord("banana", translation: "香蕉", createdAt: base),
        ]
        let questions = service.questions(on: base, from: words)
        let firstAnswer = CalendarChallengeAnswer(
            wordID: questions[0].wordID,
            form: questions[0].form,
            response: questions[0].answer,
            isCorrect: true,
            wasRevealed: false,
            answeredAt: base
        )
        service.recordAnswer(firstAnswer, for: questions[0], on: base, expectedWords: words)

        XCTAssertEqual(service.answeredCount(on: base, expectedWords: words), 1)
        XCTAssertEqual(service.dayStatus(on: base, from: words, relativeTo: base), .partial)

        let reloadedService = CalendarChallengeService(defaults: defaults, calendar: calendar)
        XCTAssertEqual(reloadedService.answeredCount(on: base, expectedWords: words), 1)
        XCTAssertEqual(reloadedService.answer(for: questions[0], on: base), firstAnswer)
        XCTAssertEqual(reloadedService.progress.schemaVersion, 1)

        XCTAssertNil(defaults.data(forKey: "saved_words"))
    }

    func testSchedulingTransitionPersistsCompletionState() {
        let (service, defaults) = makeService()
        defer {
            let suiteName = UUID().uuidString
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        let base = makeDate(year: 2026, month: 10, day: 20)
        let words = [
            makeWord("apple", translation: "苹果", createdAt: base),
            makeWord("banana", translation: "香蕉", createdAt: base),
        ]
        let questions = service.questions(on: base, from: words)

        XCTAssertEqual(service.dayStatus(on: base, from: words, relativeTo: base), .due)

        for (index, question) in questions.enumerated() {
            let answer = CalendarChallengeAnswer(
                wordID: question.wordID,
                form: question.form,
                response: index == 0 ? question.answer : "wrong",
                isCorrect: index == 0,
                wasRevealed: index != 0,
                answeredAt: base
            )
            service.recordAnswer(answer, for: question, on: base, expectedWords: words)
        }

        XCTAssertEqual(service.answeredCount(on: base, expectedWords: words), 2)
        XCTAssertEqual(service.dayStatus(on: base, from: words, relativeTo: base), .complete)
        XCTAssertNotNil(service.progress.days[service.dayKey(for: base)]?.completedAt)

        let reloadedService = CalendarChallengeService(defaults: defaults, calendar: calendar)
        XCTAssertEqual(reloadedService.progress.days[service.dayKey(for: base)]?.completedAt, base)
    }

    func testWordEntryMapsIntoCalendarWordAdapter() {
        let createdAt = makeDate(year: 2026, month: 10, day: 20)
        let entry = WordEntry(
            originalInput: "serendipity",
            normalizedKey: "serendipity",
            headword: "serendipity",
            phonetic: "/ˌserənˈdɪpəti/",
            translation: "意外新发现",
            userTranslation: "不期而遇的惊喜",
            legacyExampleSentence: "A lucky serendipity brought us together.",
            createdAt: createdAt,
            updatedAt: createdAt
        )

        let calendarWord = entry.calendarWord
        XCTAssertEqual(calendarWord.id, entry.id)
        XCTAssertEqual(calendarWord.word, "serendipity")
        // displayTranslation prefers the dictionary translation; userTranslation is the fallback.
        XCTAssertEqual(calendarWord.translation, "意外新发现")
        XCTAssertEqual(calendarWord.phonetic, "/ˌserənˈdɪpəti/")
        XCTAssertEqual(calendarWord.exampleSentence, "A lucky serendipity brought us together.")
        XCTAssertEqual(calendarWord.createdAt, createdAt)

        let dictionaryEntry = WordEntry(
            originalInput: "apple",
            normalizedKey: "apple",
            headword: "apple",
            translation: "苹果"
        )
        XCTAssertEqual(dictionaryEntry.calendarWord.translation, "苹果")
        XCTAssertNil(dictionaryEntry.calendarWord.exampleSentence)

        let userOnlyEntry = WordEntry(
            originalInput: "made-up-word",
            normalizedKey: "made-up-word",
            headword: "made-up-word",
            userTranslation: "自造词"
        )
        XCTAssertEqual(userOnlyEntry.calendarWord.translation, "自造词")
    }

    func testGeneratedQuestionsCarryTargetAndTranslationForFullPageCards() {
        let (service, _) = makeService()
        let base = makeDate(year: 2026, month: 10, day: 20)
        let words = [
            makeWord("apple", translation: "苹果", createdAt: base),
            makeWord("banana", translation: "香蕉", createdAt: base),
        ]

        let questions = service.questions(on: base, from: words)

        XCTAssertEqual(questions.count, 2)
        for question in questions {
            let word = words.first { $0.id == question.wordID }!
            XCTAssertEqual(question.target, word.word)
            XCTAssertEqual(question.targetTranslation, word.translation)
        }
    }

    func testSpellingHintSlotsRevealLettersInOrderAndKeepSeparatorsVisible() {
        XCTAssertEqual(
            SpellingHintSlots.tokens(for: "apple", revealedCount: 0),
            ["", "", "", "", ""]
        )
        XCTAssertEqual(
            SpellingHintSlots.tokens(for: "apple", revealedCount: 2),
            ["a", "p", "", "", ""]
        )
        XCTAssertEqual(
            SpellingHintSlots.tokens(for: "mother-in-law", revealedCount: 3),
            ["m", "o", "t", "", "", "", "-", "", "", "-", "", "", ""]
        )
        // Spaces stay visible and do not consume hint budget.
        XCTAssertEqual(
            SpellingHintSlots.tokens(for: "ice cream", revealedCount: 1),
            ["i", "", "", " ", "", "", "", "", ""]
        )
        XCTAssertEqual(SpellingHintSlots.letterCount(of: "mother-in-law"), 11)
        XCTAssertEqual(SpellingHintSlots.letterCount(of: "ice cream"), 8)
        // Over-revealing is clamped by the view layer; the helper itself stays total.
        XCTAssertEqual(
            SpellingHintSlots.tokens(for: "go", revealedCount: 5),
            ["g", "o"]
        )
    }
}
