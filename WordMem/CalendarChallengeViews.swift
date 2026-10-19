import AVFoundation
import SwiftUI

// MARK: - Calendar home

struct CalendarHomeView: View {
    @ObservedObject var storageManager: LocalStorageManager
    @ObservedObject private var challengeService: CalendarChallengeService

    @State private var displayedMonth = Date()
    @State private var selectedDate = Date()
    @State private var monthTitle = ""

    private let calendar = Calendar.current

    init(storageManager: LocalStorageManager, challengeService: CalendarChallengeService) {
        self.storageManager = storageManager
        self.challengeService = challengeService
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    monthNavigation
                    weekdayHeader
                    monthGrid
                    selectedDaySummary
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("日历")
            .navigationBarTitleDisplayMode(.large)
            .onAppear(perform: synchronizeCalendar)
            .onReceive(storageManager.$words) { _ in
                // Reading the current value in synchronizeCalendar keeps day summaries
                // aligned after manual entry or JSON import.
                synchronizeCalendar()
            }
        }
        .navigationViewStyle(.stack)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("每日挑战")
                .font(.title2.bold())
            Text("复习安排只保存在这台 iPhone 上。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var monthNavigation: some View {
        HStack {
            Button {
                changeMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("上一个月")

            Text(monthTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)

            Button {
                changeMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("下一个月")
        }
        .padding(.vertical, 2)
    }

    private var weekdayHeader: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let firstWeekday = calendar.firstWeekday
        return HStack(spacing: 5) {
            ForEach(0..<7, id: \.self) { index in
                Text(symbols[(firstWeekday + index - 1) % 7])
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        let days = monthDays()
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7),
            spacing: 5
        ) {
            ForEach(days) { dayItem in
                if let date = dayItem.date {
                    dayCell(for: date)
                } else {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(for date: Date) -> some View {
        let status = challengeService.dayStatus(
            on: date,
            from: storageManager.words,
            relativeTo: Date()
        )
        let isAvailable = status == .due || status == .partial || status == .complete
        let accessibility = accessibilityText(for: date, status: status)

        if isAvailable {
            NavigationLink(destination: CalendarChallengeView(date: date, storageManager: storageManager, challengeService: challengeService)) {
                DayCellContent(date: date, status: status, isSelected: calendar.isDate(selectedDate, inSameDayAs: date))
            }
            .buttonStyle(.plain)
            .accessibilityValue(accessibility)
            .accessibilityLabel(accessibility)
            .accessibilityAddTraits(.isButton)
        } else {
            DayCellContent(date: date, status: status, isSelected: calendar.isDate(selectedDate, inSameDayAs: date))
                .accessibilityValue(accessibility)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibility)
                .onTapGesture {
                    selectedDate = date
                }
        }
    }

    private var selectedDaySummary: some View {
        let status = challengeService.dayStatus(on: selectedDate, from: storageManager.words)
        let dueCount = challengeService.dueWords(on: selectedDate, from: storageManager.words).count
        let answeredCount = challengeService.answeredCount(
            on: selectedDate,
            expectedWords: challengeService.dueWords(on: selectedDate, from: storageManager.words)
        )
        let isAvailable = status == .due || status == .partial || status == .complete

        return VStack(alignment: .leading, spacing: 12) {
            Text("\(monthDayFormatter.string(from: selectedDate)) 概览")
                .font(.headline)

            HStack {
                Text(status.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(status.color)
                Spacer()
                if dueCount > 0 {
                    Text("已答 \(answeredCount)/\(dueCount)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if storageManager.words.isEmpty {
                Text("单词本还没有单词。请回到「单词本」添加或导入。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if status == .future {
                Text("未来的挑战还未开放。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if status == .empty || status == .rest {
                Text("这一天没有安排复习。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if isAvailable {
                NavigationLink(
                    destination: CalendarChallengeView(
                        date: selectedDate,
                        storageManager: storageManager,
                        challengeService: challengeService
                    )
                ) {
                    Label(status == .complete ? "查看挑战" : "开始挑战", systemImage: "play.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }

        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .accessibilityElement(children: .combine)
    }

    private func synchronizeCalendar() {
        let now = Date()
        selectedDate = calendar.startOfDay(for: now)
        displayedMonth = calendar.startOfDay(for: now)
        updateMonthTitle()
    }

    private func changeMonth(_ direction: Int) {
        guard let nextMonth = calendar.date(byAdding: .month, value: direction, to: displayedMonth) else {
            return
        }
        displayedMonth = calendar.startOfDay(for: nextMonth)
        updateMonthTitle()
    }

    private func updateMonthTitle() {
        monthTitle = monthFormatter.string(from: displayedMonth)
    }

    private func monthDays() -> [CalendarDayItem] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else {
            return []
        }

        let firstDayOffset = calendar.component(.weekday, from: monthInterval.start) - calendar.firstWeekday
        let blankCount = max(0, firstDayOffset)
        let leadingBlanks = (0..<blankCount).map { offset in
            CalendarDayItem(date: nil, id: "blank-\(monthInterval.start.timeIntervalSince1970)-\(offset)")
        }
        let dayCount = calendar.range(of: .day, in: .month, for: monthInterval.start)?.count ?? 0
        let dayDates = (0..<dayCount).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: monthInterval.start)
        }
        let dayItems = dayDates.map { CalendarDayItem(date: calendar.startOfDay(for: $0), id: "\(calendar.startOfDay(for: $0).timeIntervalSince1970)") }
        return leadingBlanks + dayItems
    }

    private func accessibilityText(for date: Date, status: CalendarChallengeDayStatus) -> String {
        let dayText = dayFormatter.string(from: date)
        let statusText = status == .empty ? "无任务" : status.title
        let suffix = status == .due || status == .partial || status == .complete ? "可打开挑战" : "不可打开挑战"
        return "\(dayText)，\(statusText)，\(suffix)。"
    }

    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.dateFormat = "yyyy年M月"
        return formatter
    }

    private var monthDayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.dateFormat = "M月d日"
        return formatter
    }

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.dateFormat = "M月d日"
        return formatter
    }
}

private struct CalendarDayItem: Identifiable {
    let date: Date?
    let id: String
}

private struct DayCellContent: View {
    let date: Date
    let status: CalendarChallengeDayStatus
    let isSelected: Bool

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        formatter.locale = .current
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(dayNumber)
                .font(.footnote.weight(.bold))
                .foregroundStyle(status.cellForeground)
            Circle()
                .fill(status.indicator)
                .frame(width: 7, height: 7)
                .opacity(status == .empty ? 0 : 1)
        }
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color(.secondarySystemGroupedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .cornerRadius(13)
        .overlay(alignment: .bottom) {
            if status != .empty && status != .rest {
                Text(status.badge)
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(status.color)
                    .cornerRadius(4)
                    .offset(y: -3)
            }
        }
    }
}

// MARK: - Day challenge

struct CalendarChallengeView: View {
    let date: Date
    @ObservedObject var storageManager: LocalStorageManager
    @ObservedObject var challengeService: CalendarChallengeService

    private var questions: [CalendarChallengeQuestion] {
        challengeService.questions(on: date, from: storageManager.words)
    }

    private var answeredWords: Set<UUID> {
        let expectedIDs = Set(questions.map(\.wordID))
        return Set(
            questions.compactMap { question in
                challengeService.answer(for: question, on: date)
            }
            .filter { expectedIDs.contains($0.wordID) }
            .map(\.wordID)
        )
    }

    private var completedCount: Int {
        challengeService.answeredCount(on: date, expectedWords: challengeService.dueWords(on: date, from: storageManager.words))
    }

    var body: some View {
        let allQuestions = questions
        let completed = !allQuestions.isEmpty && completedCount == allQuestions.count

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                progressHeader(total: allQuestions.count, completed: completedCount, isComplete: completed)

                if allQuestions.isEmpty {
                    emptyState
                } else {
                    if completed {
                        completionSummary(correctCount: allQuestions.filter { question in
                            challengeService.answer(for: question, on: date)?.isCorrect == true
                        }.count, totalCount: allQuestions.count)
                    }

                    LazyVStack(spacing: 14) {
                        ForEach(allQuestions) { question in
                            ChallengeQuestionCard(date: date, question: question, storageManager: storageManager, challengeService: challengeService)
                        }
                    }

                    Text("记录只保存在这台 iPhone 上。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("\(shortDateFormatter.string(from: date))挑战")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("这一天没有可挑战单词")
                .font(.headline)
            Text("请选择有任务的日期。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func progressHeader(total: Int, completed: Int, isComplete: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isComplete ? "挑战完成" : "进行中")
                    .font(.headline)
                Spacer()
                Text("\(completed)/\(total)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: total == 0 ? 1 : Double(completed), total: Double(total))
                .tint(isComplete ? .green : .accentColor)
            if !isComplete {
                Text("可随时离开，已提交的答案会保留。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func completionSummary(correctCount: Int, totalCount: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("已完成 \(correctCount)/\(totalCount) 题正确")
                    .font(.headline)
                Text("答案已保存在本机。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color.green.opacity(0.12))
        .cornerRadius(16)
        .accessibilityElement(children: .combine)
    }

    private var shortDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        formatter.locale = .current
        return formatter
    }
}

private struct ChallengeQuestionCard: View {
    let date: Date
    let question: CalendarChallengeQuestion
    @ObservedObject var storageManager: LocalStorageManager
    @ObservedObject var challengeService: CalendarChallengeService

    @State private var selectedOption: String?
    @State private var spelling = ""
    @State private var attemptCount = 0
    @State private var feedback: ChallengeFeedback?
    @StateObject private var speaker = ChallengeSpeaker()

    private var savedAnswer: CalendarChallengeAnswer? {
        challengeService.answer(for: question, on: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(question.form.title)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12))
                    .cornerRadius(8)
                Spacer()
                if savedAnswer != nil {
                    Image(systemName: savedAnswer?.isCorrect == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(savedAnswer?.isCorrect == true ? .green : .red)
                }
            }

            Text(question.prompt)
                .font(.headline)

            if let exampleText = question.exampleText {
                Text(exampleText)
                    .font(.body)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(10)
            }

            if question.form == .listeningChoice {
                HStack(spacing: 10) {
                    Button {
                        speaker.play(question.answer)
                    } label: {
                        Label("播放发音", systemImage: "speaker.wave.2.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        speaker.play(question.answer, rate: 0.28)
                    } label: {
                        Label("慢速", systemImage: "tortoise")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
                if !speaker.isAvailable {
                    Text("当前设备没有英文语音。可切换到其他题目形式。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("可见提示：\(question.answer)")
                        .font(.subheadline.weight(.semibold))
                }
            }

            if savedAnswer == nil {
                answerControls
            } else {
                Text(savedAnswer?.isCorrect == true ? "回答正确。" : "已记录。正确答案：\(question.answer)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(savedAnswer?.isCorrect == true ? .green : .secondary)
            }

            if let feedback = feedback {
                Text(feedback.text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(feedback.isCorrect ? .green : .red)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            if let hint = question.hint, savedAnswer == nil {
                Text("提示：\(hint)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var answerControls: some View {
        if question.options.isEmpty {
            spellingControls
        } else {
            optionControls
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
                        .font(.body)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.bordered)
                .disabled(feedback?.isRetry == true)
            }

            if feedback?.isRetry == true {
                Button {
                    feedback = nil
                    selectedOption = nil
                    attemptCount = 0
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    reveal()
                } label: {
                    Label("跳过并显示答案", systemImage: "eye")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var spellingControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("输入英文单词", text: $spelling)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(submitSpelling)

            HStack(spacing: 10) {
                Button {
                    submitSpelling()
                } label: {
                    Text("提交")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(spelling.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if feedback?.isRetry == true {
                    Button {
                        feedback = nil
                        spelling = ""
                    } label: {
                        Text("重试")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }

                if feedback?.isRetry == true {
                    Button {
                        reveal()
                    } label: {
                        Text("跳过")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

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
            feedback = ChallengeFeedback(text: "仍不对。可跳过查看答案。", isCorrect: false, isRetry: true)
        }
    }

    private func reveal() {
        feedback = ChallengeFeedback(text: "已显示答案。", isCorrect: false, isRetry: false)
        save(
            response: question.answer,
            isCorrect: false,
            revealed: true
        )
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
            expectedWords: challengeService.dueWords(on: date, from: storageManager.words)
        )
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - Local presentation helpers

private struct ChallengeFeedback {
    let text: String
    let isCorrect: Bool
    let isRetry: Bool
}

final class ChallengeSpeaker: ObservableObject {
    @Published private(set) var isSpeaking = false
    let isAvailable = AVSpeechSynthesisVoice(language: "en-US") != nil
    private let synthesizer = AVSpeechSynthesizer()

    func play(_ text: String, rate: Float = 0.5) {
        guard isAvailable, !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = rate
        synthesizer.speak(utterance)
    }
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

extension CalendarChallengeDayStatus {
    var title: String {
        switch self {
        case .empty: return "无任务"
        case .rest: return "休息日"
        case .future: return "未来任务"
        case .due: return "待完成"
        case .partial: return "部分完成"
        case .complete: return "已完成"
        }
    }

    var color: Color {
        switch self {
        case .empty: return .secondary
        case .rest: return .teal
        case .future: return .gray
        case .due: return .blue
        case .partial: return .orange
        case .complete: return .green
        }
    }

    var indicator: Color {
        color
    }

    var cellForeground: Color {
        switch self {
        case .empty, .rest: return .secondary
        case .future: return .secondary
        case .due, .partial, .complete: return .primary
        }
    }

    var badge: String {
        switch self {
        case .empty: return ""
        case .rest: return "休"
        case .future: return "未开"
        case .due: return "待"
        case .partial: return "半"
        case .complete: return "成"
        }
    }
}
