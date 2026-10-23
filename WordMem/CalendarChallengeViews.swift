import SwiftUI

// MARK: - Calendar home

struct CalendarHomeView: View {
    var words: [CalendarWord]
    @ObservedObject private var challengeService: CalendarChallengeService

    @State private var displayedMonth = Date()
    @State private var selectedDate = Date()
    @State private var monthTitle = ""
    #if DEBUG
    @State private var deepLinkedChallenge = false
    #endif

    private let calendar = Calendar.current

    init(words: [CalendarWord], challengeService: CalendarChallengeService) {
        self.words = words
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
            #if DEBUG
            .background(
                NavigationLink(isActive: $deepLinkedChallenge) {
                    CalendarChallengeView(
                        date: calendar.date(byAdding: .day, value: DebugDeepLink.challengeDateOffset, to: Date()) ?? Date(),
                        words: words,
                        challengeService: challengeService
                    )
                } label: {
                    EmptyView()
                }
                .hidden()
            )
            .onAppear {
                if DebugDeepLink.openChallenge {
                    deepLinkedChallenge = true
                }
            }
            #endif
            .onChange(of: words) { _, _ in
                // Reading the current value in synchronizeCalendar keeps day summaries
                // aligned after the wordbook changes.
                synchronizeCalendar()
            }
        }
        .navigationViewStyle(.stack)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("每日挑战")
                .font(.title2.bold())
            Text("复习只使用你补充的中文释义，并保存在这台 iPhone 上。")
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
            from: words,
            relativeTo: Date()
        )
        let isAvailable = status == .due || status == .partial || status == .complete
        let accessibility = accessibilityText(for: date, status: status)

        if isAvailable {
            NavigationLink(destination: CalendarChallengeView(date: date, words: words, challengeService: challengeService)) {
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
        let status = challengeService.dayStatus(on: selectedDate, from: words)
        let dueCount = challengeService.dueWords(on: selectedDate, from: words).count
        let answeredCount = challengeService.answeredCount(
            on: selectedDate,
            expectedWords: challengeService.dueWords(on: selectedDate, from: words)
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

            if words.isEmpty {
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
                        words: words,
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
