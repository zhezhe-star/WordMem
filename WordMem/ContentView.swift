import AVFoundation
import SwiftData
import SwiftUI

enum WordMemRoute: Hashable {
    case detail(UUID)
}

struct AddWordFeedback: Identifiable {
    let id = UUID()
    let isAdded: Bool
    let canUndo: Bool
    let message: String
    let entry: WordEntry

    @MainActor
    init(_ outcome: AddWordOutcome) {
        let isAdded: Bool
        let message: String

        switch outcome {
        case .added:
            isAdded = true
            message = "已添加 \(outcome.entry.headword)"
        case .duplicate:
            isAdded = false
            message = "已在单词本 \(outcome.entry.headword)"
        }

        self.isAdded = isAdded
        self.canUndo = isAdded
        self.message = message
        self.entry = outcome.entry
    }
}

@MainActor
final class WordImportMaintenanceCoordinator {
    private var isRunning = false

    func run(_ operation: @MainActor () async throws -> Void) async rethrows {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        try await operation()
    }
}

extension AddWordFeedback: Equatable {
    static func == (lhs: AddWordFeedback, rhs: AddWordFeedback) -> Bool {
        lhs.id == rhs.id
    }
}

struct ContentView: View {
    @Query(sort: \WordEntry.createdAt) private var entries: [WordEntry]
    @StateObject private var challengeService = CalendarChallengeService()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            WordbookView()
                .tabItem {
                    Label("单词本", systemImage: "books.vertical")
                }
                .tag(0)

            CalendarHomeView(
                words: entries.map(\.calendarWord),
                challengeService: challengeService
            )
            .tabItem {
                Label("日历", systemImage: "calendar")
            }
            .tag(1)
        }
        .onAppear {
            #if DEBUG
                if DebugDeepLink.openChallenge {
                    selectedTab = 1
                }
            #endif
        }
    }
}

struct WordbookView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WordEntry.updatedAt, order: .reverse) private var words: [WordEntry]
    @State private var route: [WordMemRoute] = []
    @State private var activeImportSheet: WordImportSheet?
    @State private var batchImportMessage: String?
    @State private var feedback: AddWordFeedback?
    @State private var alertMessage: String?
    @State private var queueAttentionMessage: String?
    @State private var maintenanceCoordinator = WordImportMaintenanceCoordinator()

    @State private var dictionaryService: any DictionaryLookupService =
        BareWordDictionaryLookupService()

    var body: some View {
        NavigationStack(path: $route) {
            Group {
                if words.isEmpty {
                    emptyState
                } else {
                    wordList
                }
            }
            .navigationTitle("WordMem")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(WordImportSheet.allCases) { sheet in
                            Button {
                                activeImportSheet = sheet
                            } label: {
                                Label(sheet.title, systemImage: sheet.systemImage)
                            }
                        }
                    } label: {
                        Label("添加单词", systemImage: "plus")
                    }
                    .accessibilityIdentifier("addWordButton")
                }
            }
            .navigationDestination(for: WordMemRoute.self) { route in
                switch route {
                case .detail(let id):
                    if let word = words.first(where: { $0.id == id }) {
                        WordEntryDetailView(entry: word)
                    }
                }
            }
            .sheet(item: $activeImportSheet) { sheet in
                switch sheet {
                case .manual:
                    AddWordView(dictionaryService: dictionaryService) { outcome in
                        presentFeedback(for: outcome)
                    }
                    .presentationDetents([.height(280)])
                    .presentationDragIndicator(.visible)
                case .image:
                    ImageImportView(dictionaryService: dictionaryService) { summary in
                        batchImportMessage = summary.message
                    }
                    .presentationDragIndicator(.visible)
                case .text:
                    TextImportView(dictionaryService: dictionaryService) { summary in
                        batchImportMessage = summary.message
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
            .alert(
                "添加失败",
                isPresented: .init(
                    get: { alertMessage != nil },
                    set: { if !$0 { alertMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
            .overlay(alignment: .bottom) {
                if let feedback {
                    AddWordFeedbackView(feedback: feedback) {
                        removeFeedback(feedback.entry)
                    }
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: feedback)
            .alert(
                "导入完成",
                isPresented: .init(
                    get: { batchImportMessage != nil },
                    set: { if !$0 { batchImportMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(batchImportMessage ?? "")
            }
            .alert(
                "导入提示",
                isPresented: .init(
                    get: { queueAttentionMessage != nil },
                    set: { if !$0 { queueAttentionMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(queueAttentionMessage ?? "")
            }
            .task {
                initializeDictionaryService()
                await performImportMaintenance()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            ) { _ in
                Task {
                    await performImportMaintenance()
                }
            }
            .task(id: feedback?.id) {
                guard feedback != nil else { return }
                try? await Task.sleep(for: .seconds(4))
                withAnimation(.snappy) {
                    self.feedback = nil
                }
            }
        }
    }
    private var emptyState: some View {
        ContentUnavailableView {
            Label("单词本还是空的", systemImage: "book.closed")
        } description: {
            Text("输入一个单词，WordMem 会从本地词典补充它的完整信息。")
        } actions: {
            Button("添加第一个单词") {
                activeImportSheet = .manual
            }
            .buttonStyle(.glassProminent)
        }
    }

    private var wordList: some View {
        List {
            ForEach(words) { word in
                NavigationLink(value: WordMemRoute.detail(word.id)) {
                    WordRowView(entry: word)
                }
            }
            .onDelete(perform: deleteWords)
        }
        .listStyle(.insetGrouped)
    }

    private func presentFeedback(for outcome: AddWordOutcome) {
        withAnimation(.snappy) {
            feedback = AddWordFeedback(outcome)
        }
    }

    private func removeFeedback(_ entry: WordEntry) {
        do {
            try WordbookRepository(modelContext: modelContext).undoAdd(entry)
            withAnimation(.snappy) {
                feedback = nil
            }
        } catch {
            alertMessage = "撤销失败，请重试。"
        }
    }

    private func deleteWords(at offsets: IndexSet) {
        let entries = offsets.map { words[$0] }

        do {
            try WordbookRepository(modelContext: modelContext).deleteWords(entries)
        } catch {
            modelContext.rollback()
            alertMessage = "删除失败，请重试。"
        }
    }

    private func migrateLegacyWordbook() async {
        do {
            // Share 与翻译扩展都写入 App Group 的 saved_words，迁移时优先读取它。
            let extensionSharedDefaults =
                UserDefaults(suiteName: WordImportSubmissionQueue.appGroupIdentifier) ?? .standard
            let localDictionary = dictionaryService as? SQLiteDictionaryLookupService
            try await LegacyWordbookMigrator.migrateIfNeeded(
                defaults: extensionSharedDefaults,
                into: modelContext,
                dictionaryService: localDictionary
            )
        } catch {
            alertMessage = "旧单词本迁移失败。WordMem 已保留原始数据。"
        }
    }

    private func performImportMaintenance() async {
        let extensionSharedDefaults =
            UserDefaults(suiteName: WordImportSubmissionQueue.appGroupIdentifier)
            ?? .standard
        try? await maintenanceCoordinator.run { [self] in
            await migrateLegacyWordbook()
            do {
                try WordImportContextMigrator.backfillSubmissionIdentity(
                    in: modelContext,
                    defaults: extensionSharedDefaults
                )
                let result = try await WordImportSubmissionMigrator.processPendingSubmissions(
                    baseDirectory: WordImportSubmissionQueue.defaultBaseDirectory(),
                    legacyDefaults: extensionSharedDefaults,
                    into: modelContext,
                    dictionaryService: dictionaryService
                )
                queueAttentionMessage = result.attentionMessage
                try WordImportContextMigrator.backfillEntryIDs(
                    in: modelContext,
                    defaults: extensionSharedDefaults
                )
            } catch {
                alertMessage = "导入记录迁移失败。WordMem 已保留原始数据。"
            }
        }
    }

    private func initializeDictionaryService() {
        guard dictionaryService is BareWordDictionaryLookupService else { return }

        do {
            dictionaryService = try SQLiteDictionaryLookupService()
        } catch {
            alertMessage = "本地词典加载失败。核心记录功能仍可用。"
        }
    }
}

private struct WordRowView: View {
    let entry: WordEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.headword)
                    .font(.headline)

                Spacer()

                LookupStatusBadge(status: entry.lookupStatus)
            }

            if let phonetic = entry.phonetic, !phonetic.isEmpty {
                Text(phonetic)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if entry.displayTranslation.isEmpty {
                Text("本地词典暂未收录，已保存为待补充。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(entry.displayTranslation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

struct LookupStatusBadge: View {
    let status: LookupStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.tint.opacity(0.12), in: .capsule)
            .foregroundStyle(status.tint)
    }
}

private struct AddWordFeedbackView: View {
    let feedback: AddWordFeedback
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: feedback.isAdded ? "checkmark.circle.fill" : "checkmark.circle")
                .foregroundStyle(.green)

            Text(feedback.message)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            if feedback.canUndo {
                Button("撤销", action: undo)
                    .buttonStyle(.glass)
                    .controlSize(.small)
            } else {
                NavigationLink(value: WordMemRoute.detail(feedback.entry.id)) {
                    Text("查看")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

extension LookupStatus {
    var tint: Color {
        switch self {
        case .enriched: .green
        case .lemmaResolved: .blue
        case .autoCorrected: .orange
        case .ambiguousResolved: .indigo
        case .userSaved: .mint
        case .notFound: .secondary
        }
    }
}

struct WordEntryDetailView: View {
    let entry: WordEntry
    @Query private var importContexts: [WordImportContext]
    @State private var synthesizer = AVSpeechSynthesizer()

    init(entry: WordEntry) {
        self.entry = entry
        let entryID = entry.id
        _importContexts = Query(
            filter: #Predicate<WordImportContext> { context in
                context.entryID == entryID
            },
            sort: [SortDescriptor(\WordImportContext.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.headword)
                            .font(.largeTitle.bold())

                        Spacer()

                        LookupStatusBadge(status: entry.lookupStatus)
                    }

                    if let phonetic = entry.phonetic, !phonetic.isEmpty {
                        Text(phonetic)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    if entry.originalInput.localizedCaseInsensitiveCompare(entry.headword)
                        != .orderedSame
                    {
                        Text("输入：\(entry.originalInput)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                Button {
                    playWord()
                } label: {
                    Label("播放发音", systemImage: "speaker.wave.2")
                }
            }

            if entry.senses.isEmpty {
                Section("释义") {
                    if entry.userTranslation.isEmpty {
                        Text("本地词典暂未收录。")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("导入释义")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tint)
                            Text(entry.userTranslation)
                        }
                        Text("本地词典暂未收录，词典释义可稍后补充。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section("释义") {
                    ForEach(entry.senses, id: \.self) { sense in
                        VStack(alignment: .leading, spacing: 4) {
                            if let partOfSpeech = sense.partOfSpeech {
                                Text(partOfSpeech)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tint)
                            }

                            Text(sense.chinese)
                                .font(.body)

                            if let english = sense.english {
                                Text(english)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    if !entry.userTranslation.isEmpty,
                        entry.userTranslation != entry.translation
                    {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("我的解释")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tint)

                            Text(entry.userTranslation)
                                .font(.body)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if let userExample = entry.userExample, !userExample.isEmpty {
                Section("用户例句") {
                    Text(userExample)
                }
            }

            if entry.hasLegacyUserData {
                Section("旧记录") {
                    if let sentence = entry.legacyExampleSentence, !sentence.isEmpty {
                        Text(sentence)

                        if let translated = entry.legacyTranslatedExampleSentence,
                            !translated.isEmpty
                        {
                            Text(translated)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let supplementary = entry.legacyExample, !supplementary.isEmpty {
                        Text(supplementary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("导入记录") {
                if importContexts.isEmpty {
                    Text("没有导入来源记录。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(importContexts) { context in
                        WordImportContextView(context: context)
                    }
                }
            }

            if !entry.forms.isEmpty {
                Section("词形") {
                    ForEach(entry.forms, id: \.self) { form in
                        LabeledContent(formKindName(form.kind), value: form.value)
                    }
                }
            }

            if !entry.tags.isEmpty {
                Section("考试标签") {
                    FlowTagsView(tags: entry.tags)
                        .padding(.vertical, 2)
                }
            }

            Section("记录") {
                LabeledContent("创建时间") {
                    Text(entry.createdAt, style: .date)
                }

                LabeledContent("更新时间") {
                    Text(entry.updatedAt, style: .date)
                }
            }
        }
        .navigationTitle(entry.headword)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func playWord() {
        let utterance = AVSpeechUtterance(string: entry.headword)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        synthesizer.speak(utterance)
    }

    private func formKindName(_ kind: WordForm.Kind) -> String {
        switch kind {
        case .inflection: "变化形式"
        case .plural: "复数"
        case .pastTense: "过去式"
        case .pastParticiple: "过去分词"
        case .presentParticiple: "现在分词"
        case .thirdPersonSingular: "第三人称单数"
        case .comparative: "比较级"
        case .superlative: "最高级"
        case .adverb: "副词"
        case .verb: "动词"
        }
    }
}

private struct WordImportContextView: View {
    let context: WordImportContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(context.source.displayName, systemImage: context.source.systemImage)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.tint.opacity(0.10), in: .capsule)

                Spacer()

                Text(context.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let sourceText = context.sourceText, !sourceText.isEmpty {
                Text("来源文本")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(sourceText)
                    .font(.subheadline)
                    .lineLimit(4)
            }

            if let recognizedText = context.recognizedText, !recognizedText.isEmpty,
                recognizedText != context.sourceText
            {
                Text("识别文本")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(recognizedText)
                    .font(.subheadline)
                    .lineLimit(4)
            }

            if let note = context.metadata["userNote"], !note.isEmpty {
                Text("记忆笔记：\(note)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let example = context.metadata["userExample"], !example.isEmpty {
                Text("用户例句：\(example)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let imageData = context.imageData, !imageData.isEmpty,
                let image = UIImage(data: imageData)
            {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 10))
            }

            if let candidate = context.selectedCandidate, !candidate.isEmpty {
                Text("选择词：\(candidate)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct FlowTagsView: View {
    let tags: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.tint.opacity(0.10), in: .capsule)
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }

            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
