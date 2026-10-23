import SwiftUI

#if DEBUG
    /// Environment-driven entry points so the challenge flow can be opened
    /// directly in a (headless) simulator for UI verification:
    /// `SIMCTL_CHILD_WORDMEM_OPEN_CHALLENGE=1 xcrun simctl launch …` opens the
    /// calendar tab and pushes the challenge for today plus
    /// `WORDMEM_CHALLENGE_DATE_OFFSET` days; `WORDMEM_CHALLENGE_PAGE` selects the
    /// initial question index (question count = completion page).
    enum DebugDeepLink {
        static var openChallenge: Bool {
            ProcessInfo.processInfo.environment["WORDMEM_OPEN_CHALLENGE"] == "1"
        }

        static var challengeDateOffset: Int {
            Int(ProcessInfo.processInfo.environment["WORDMEM_CHALLENGE_DATE_OFFSET"] ?? "") ?? 0
        }

        static var challengePage: Int? {
            Int(ProcessInfo.processInfo.environment["WORDMEM_CHALLENGE_PAGE"] ?? "")
        }
    }
#endif

// MARK: - Full-screen challenge flow

/// One-question-per-page challenge experience. Answering a question briefly
/// shows feedback, then automatically slides to the next page; swiping back
/// to an answered question shows the recorded, locked answer.
struct CalendarChallengeView: View {
    let date: Date
    var words: [CalendarWord]
    @ObservedObject var challengeService: CalendarChallengeService

    @Environment(\.dismiss) private var dismiss
    @State private var currentPageID: String?

    private static let completionPageID = "completion"

    private var questions: [CalendarChallengeQuestion] {
        challengeService.questions(on: date, from: words)
    }

    private var dueWords: [CalendarWord] {
        challengeService.dueWords(on: date, from: words)
    }

    private var answeredCount: Int {
        challengeService.answeredCount(on: date, expectedWords: dueWords)
    }

    var body: some View {
        let allQuestions = questions

        VStack(spacing: 0) {
            topBar(total: allQuestions.count)

            if allQuestions.isEmpty {
                emptyState
            } else {
                TabView(selection: $currentPageID) {
                    ForEach(allQuestions) { question in
                        ChallengeQuestionPage(
                            date: date,
                            question: question,
                            words: words,
                            challengeService: challengeService,
                            onAnswerRecorded: scheduleAdvance
                        )
                        .tag(question.id)
                    }

                    completionPage(questions: allQuestions)
                        .tag(Self.completionPageID)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard currentPageID == nil else { return }
            #if DEBUG
                if let page = DebugDeepLink.challengePage {
                    currentPageID =
                        allQuestions.indices.contains(page)
                        ? allQuestions[page].id
                        : Self.completionPageID
                    return
                }
            #endif
            currentPageID =
                allQuestions.first(where: {
                    challengeService.answer(for: $0, on: date) == nil
                })?.id ?? Self.completionPageID
        }
    }

    private func topBar(total: Int) -> some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(Circle())
                }
                .accessibilityLabel("关闭挑战")

                Text("\(shortDateFormatter.string(from: date))挑战")
                    .font(.headline)

                Spacer()

                Text("\(answeredCount) / \(total)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: total == 0 ? 0 : Double(answeredCount), total: Double(max(total, 1)))
                .tint(answeredCount == total && total > 0 ? .green : .accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("这一天没有可挑战单词")
                .font(.headline)
            Text("请选择有任务的日期。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func completionPage(questions: [CalendarChallengeQuestion]) -> some View {
        let correctCount = questions.filter {
            challengeService.answer(for: $0, on: date)?.isCorrect == true
        }.count
        let missedWords = questions.filter {
            challengeService.answer(for: $0, on: date)?.isCorrect == false
        }

        return VStack(spacing: 18) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("挑战完成")
                .font(.title.bold())

            Text("答对 \(correctCount)/\(questions.count) 题")
                .font(.headline)
                .foregroundStyle(.secondary)

            if !missedWords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("需要再巩固")
                        .font(.subheadline.weight(.semibold))
                    ForEach(missedWords) { question in
                        HStack {
                            Text(question.target)
                                .font(.body.weight(.medium))
                            Spacer()
                            Text(question.targetTranslation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: 420)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .padding(.horizontal, 24)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("完成")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func nextPageID(after questionID: String) -> String {
        let ids = questions.map(\.id)
        guard let index = ids.firstIndex(of: questionID), index + 1 < ids.count else {
            return Self.completionPageID
        }
        return ids[index + 1]
    }

    private func scheduleAdvance(from questionID: String) {
        let next = nextPageID(after: questionID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            // The user may have swiped away during the feedback beat; only
            // advance if this question is still the visible page.
            guard currentPageID == questionID else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                currentPageID = next
            }
        }
    }

    private var shortDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        formatter.locale = .current
        return formatter
    }
}

// MARK: - One question per page

private struct ChallengeQuestionPage: View {
    let date: Date
    let question: CalendarChallengeQuestion
    var words: [CalendarWord]
    @ObservedObject var challengeService: CalendarChallengeService
    let onAnswerRecorded: (String) -> Void
    @EnvironmentObject private var speaker: EnglishPronunciationPlayer

    @State private var selectedOption: String?
    @State private var spelling = ""
    @State private var attemptCount = 0
    @State private var feedback: ChallengeFeedback?
    @State private var revealedLetterCount = 0
    private var savedAnswer: CalendarChallengeAnswer? {
        challengeService.answer(for: question, on: date)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text(question.form.title)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.12))
                    .cornerRadius(8)
                Spacer()
                if let savedAnswer {
                    Image(systemName: savedAnswer.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(savedAnswer.isCorrect ? .green : .red)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)

            Spacer(minLength: 12)

            heroContent
                .padding(.horizontal, 24)

            Spacer(minLength: 12)

            Group {
                if let savedAnswer {
                    lockedResult(savedAnswer)
                } else {
                    answerControls
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .onDisappear {
            speaker.cancel()
        }
    }

    // MARK: Hero content per form

    @ViewBuilder
    private var heroContent: some View {
        switch question.form {
        case .meaningChoice:
            VStack(spacing: 14) {
                Text(question.target)
                    .font(.system(size: 44, weight: .bold))
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    speakerButton(text: question.target)
                }
                Text("选择正确释义")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case .listeningChoice:
            VStack(spacing: 18) {
                Button {
                    speaker.play(question.answer)
                } label: {
                    Image(systemName: speaker.isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 40))
                        .frame(width: 96, height: 96)
                        .foregroundStyle(speaker.isSpeaking ? Color.accentColor : Color.primary)
                        .background(Color.accentColor.opacity(speaker.isSpeaking ? 0.28 : 0.14))
                        .clipShape(Circle())
                }
                .accessibilityLabel("播放发音")
                .accessibilityValue(speaker.isSpeaking ? "正在播放" : "未播放")
                .accessibilityAddTraits(speaker.isSpeaking ? .isSelected : [])

                Button {
                    speaker.play(question.answer, rate: 0.28)
                } label: {
                    Label("慢速播放", systemImage: "tortoise")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("慢速播放发音")
                .accessibilityValue(speaker.isSpeaking ? "正在播放" : "未播放")
                .accessibilityAddTraits(speaker.isSpeaking ? .isSelected : [])

                if !speaker.isAvailable {
                    Text("当前设备没有英文语音。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("可见提示：\(question.answer)")
                        .font(.subheadline.weight(.semibold))
                }

                Text("听发音，选择正确单词")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case .reverseTranslation:
            VStack(spacing: 14) {
                Text(question.targetTranslation)
                    .font(.system(size: 34, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("选择对应的英文单词")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case .exampleCloze:
            VStack(spacing: 14) {
                if let exampleText = question.exampleText {
                    Text(exampleText)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .padding(18)
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(16)
                }
                Text("根据语境补全例句")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case .spellingInput:
            VStack(spacing: 16) {
                Text(question.targetTranslation)
                    .font(.system(size: 30, weight: .bold))
                    .multilineTextAlignment(.center)

                if let example = question.exampleText {
                    Text(example)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                }

                spellingSlots
            }
        }
    }

    private var spellingSlots: some View {
        let tokens = SpellingHintSlots.tokens(for: question.answer, revealedCount: revealedLetterCount)
        return HStack(spacing: 7) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                Text(token.isEmpty ? " " : token)
                    .font(.title3.weight(.semibold).monospaced())
                    .frame(minWidth: 14)
                    .overlay(alignment: .bottom) {
                        if token != " " {
                            Rectangle()
                                .fill(token.isEmpty ? Color.secondary : Color.accentColor)
                                .frame(height: 2)
                        }
                    }
            }
        }
        .accessibilityLabel(
            "答案共 \(SpellingHintSlots.letterCount(of: question.answer)) 个字母，已提示 \(min(revealedLetterCount, SpellingHintSlots.letterCount(of: question.answer))) 个"
        )
    }

    private func speakerButton(text: String) -> some View {
        Button {
            speaker.play(text)
        } label: {
            Image(systemName: speaker.isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                .font(.title3)
                .frame(width: 40, height: 40)
                .foregroundStyle(speaker.isSpeaking ? Color.accentColor : Color.primary)
                .background(Color.accentColor.opacity(speaker.isSpeaking ? 0.28 : 0.14))
                .clipShape(Circle())
        }
        .accessibilityLabel("播放 \(text) 的发音")
        .accessibilityValue(speaker.isSpeaking ? "正在播放" : "未播放")
        .accessibilityAddTraits(speaker.isSpeaking ? .isSelected : [])
    }

    // MARK: Answered (locked) state

    private func lockedResult(_ answer: CalendarChallengeAnswer) -> some View {
        VStack(spacing: 12) {
            Text(answer.isCorrect ? "回答正确" : "正确答案")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(answer.isCorrect ? .green : .secondary)

            Text(question.answer)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)

            if !answer.isCorrect, !answer.wasRevealed, normalized(answer.response) != normalized(question.answer) {
                Text("你的回答：\(answer.response)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: Answer controls

    @ViewBuilder
    private var answerControls: some View {
        VStack(spacing: 12) {
            if question.form == .spellingInput {
                spellingControls
            } else {
                optionControls
            }

            if let feedback {
                Text(feedback.text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(feedback.isCorrect ? .green : .red)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private var optionControls: some View {
        VStack(spacing: 10) {
            ForEach(question.options, id: \.self) { option in
                Button {
                    selectedOption = option
                    submit(response: option)
                } label: {
                    Text(option)
                        .font(.body.weight(.medium))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .padding(.horizontal, 12)
                        .background(optionBackground(for: option))
                        .cornerRadius(14)
                }
                .buttonStyle(.plain)
                .disabled(feedback?.isRetry == true)
            }

            if feedback?.isRetry == true {
                HStack(spacing: 10) {
                    Button {
                        feedback = nil
                        selectedOption = nil
                        attemptCount = 0
                    } label: {
                        Label("重试", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        reveal()
                    } label: {
                        Label("显示答案", systemImage: "eye")
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func optionBackground(for option: String) -> Color {
        guard feedback?.isRetry == true else {
            return Color(.secondarySystemGroupedBackground)
        }
        if option == question.answer {
            return Color.green.opacity(0.18)
        }
        if option == selectedOption {
            return Color.red.opacity(0.18)
        }
        return Color(.secondarySystemGroupedBackground)
    }

    private var spellingControls: some View {
        VStack(spacing: 10) {
            TextField("输入英文单词", text: $spelling)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(submitSpelling)

            HStack(spacing: 10) {
                let totalLetters = SpellingHintSlots.letterCount(of: question.answer)
                Button {
                    revealedLetterCount = min(revealedLetterCount + 1, totalLetters)
                } label: {
                    Label("提示", systemImage: "lightbulb")
                        .frame(minHeight: 46)
                }
                .buttonStyle(.bordered)
                .disabled(revealedLetterCount >= totalLetters || feedback?.isRetry == true)

                Button {
                    submitSpelling()
                } label: {
                    Text("提交")
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .disabled(spelling.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || feedback?.isRetry == true)
            }

            if feedback?.isRetry == true {
                HStack(spacing: 10) {
                    Button {
                        feedback = nil
                        spelling = ""
                    } label: {
                        Label("重试", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        reveal()
                    } label: {
                        Label("显示答案", systemImage: "eye")
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: Answer state machine (unchanged semantics from the list layout)

    private func submitSpelling() {
        let response = spelling.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !response.isEmpty else { return }
        submit(response: response)
    }

    private func submit(response: String) {
        let isCorrect = normalized(response) == normalized(question.answer)
        if isCorrect {
            feedback = ChallengeFeedback(text: "回答正确！", isCorrect: true, isRetry: false)
            save(response: response, isCorrect: true, revealed: false)
        } else if attemptCount < 1 {
            attemptCount += 1
            feedback = ChallengeFeedback(text: "不对，请再试一次。", isCorrect: false, isRetry: true)
        } else {
            feedback = ChallengeFeedback(text: "仍不对。可重试或显示答案。", isCorrect: false, isRetry: true)
        }
    }

    private func reveal() {
        feedback = ChallengeFeedback(text: "已显示答案。", isCorrect: false, isRetry: false)
        save(response: question.answer, isCorrect: false, revealed: true)
    }

    private func save(response: String, isCorrect: Bool, revealed: Bool) {
        challengeService.recordAnswer(
            CalendarChallengeAnswer(
                wordID: question.wordID,
                form: question.form,
                response: response,
                isCorrect: isCorrect,
                wasRevealed: revealed,
                answeredAt: Date()
            ),
            for: question,
            on: date,
            expectedWords: challengeService.dueWords(on: date, from: words)
        )
        onAnswerRecorded(question.id)
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - Spelling hint slots

/// Pure helper behind the spelling card's letter slots. Non-letter characters
/// (spaces, hyphens) are always visible; letters appear one by one as the
/// user taps the hint button.
enum SpellingHintSlots {
    static func tokens(for answer: String, revealedCount: Int) -> [String] {
        var remaining = max(0, revealedCount)
        return answer.map { character in
            guard character.isLetter else { return String(character) }
            if remaining > 0 {
                remaining -= 1
                return String(character)
            }
            return ""
        }
    }

    static func letterCount(of answer: String) -> Int {
        answer.filter(\.isLetter).count
    }
}

// MARK: - Local presentation helpers

private struct ChallengeFeedback {
    let text: String
    let isCorrect: Bool
    let isRetry: Bool
}

extension CalendarChallengeForm {
    var title: String {
        switch self {
        case .meaningChoice: return "释义选择"
        case .listeningChoice: return "听力选择"
        case .reverseTranslation: return "反向翻译"
        case .exampleCloze: return "例句填空"
        case .spellingInput: return "拼写"
        }
    }
}
