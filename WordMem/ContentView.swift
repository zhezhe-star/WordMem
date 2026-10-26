import SwiftData
import SwiftUI

enum WordMemRoute: Hashable {
    case detail(UUID)
}

struct AddWordFeedback: Identifiable, Equatable {
    let id = UUID()
    let isAdded: Bool
    let message: String
    let entryID: UUID

    @MainActor
    init(_ outcome: AddWordOutcome) {
        isAdded = outcome.isAdded
        message = outcome.isAdded ? "已添加 \(outcome.entry.headword)" : "已在单词本 \(outcome.entry.headword)"
        entryID = outcome.entry.id
    }

    static func == (lhs: AddWordFeedback, rhs: AddWordFeedback) -> Bool { lhs.id == rhs.id }
}

@MainActor
final class WordImportMaintenanceCoordinator {
    private var isRunning = false
    private let dictionary: any AuthoritativeDictionaryAuthorizing

    init(dictionary: any AuthoritativeDictionaryAuthorizing = WordNetKitAuthoritativeDictionaryProvider.shared) {
        self.dictionary = dictionary
    }

    func processPendingSubmissions(in modelContext: ModelContext) async -> String? {
        guard !isRunning else { return nil }
        isRunning = true
        defer { isRunning = false }

        do {
            let snapshot = try WordImportSubmissionQueue.snapshot()
            let repository = WordbookRepository(modelContext: modelContext)
            var completedIDs: Set<UUID> = []

            for submission in snapshot.pending {
                guard try !repository.hasCompletedImport(submission) else {
                    completedIDs.insert(submission.payloadID)
                    continue
                }
                _ = try await repository.importSubmission(submission, using: dictionary)
                completedIDs.insert(submission.payloadID)
            }
            try WordImportSubmissionQueue.remove(completedIDs)
            return WordImportSubmissionQueue.attentionMessage(for: snapshot)
        } catch {
            return "有导入记录暂时无法处理，已保留待下次启动重试。"
        }
    }
}

struct ContentView: View {
    @Query(sort: \WordEntry.createdAt) private var entries: [WordEntry]
    @StateObject private var challengeService = CalendarChallengeService()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            WordbookView()
                .tabItem { Label("单词本", systemImage: "books.vertical") }
                .tag(0)

            CalendarHomeView(
                words: entries.compactMap(\.calendarWord),
                challengeService: challengeService
            )
            .tabItem { Label("日历", systemImage: "calendar") }
            .tag(1)
        }
    }
}

struct WordbookView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WordEntry.updatedAt, order: .reverse) private var words: [WordEntry]
    @State private var route: [WordMemRoute] = []
    @State private var activeImportSheet: WordImportSheet?
    @State private var feedback: AddWordFeedback?
    @State private var alertMessage: String?
    @State private var queueAttentionMessage: String?
    @State private var maintenance = WordImportMaintenanceCoordinator()
    @State private var isAttributionPresented = false
    @State private var dictionary = WordNetKitAuthoritativeDictionaryProvider.shared

    var body: some View {
        NavigationStack(path: $route) {
            Group {
                if words.isEmpty { emptyState } else { wordList }
            }
            .navigationTitle("WordMem")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isAttributionPresented = true
                        } label: {
                            Label("词典授权", systemImage: "checkmark.seal")
                        }

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
            .navigationDestination(for: WordMemRoute.self) { routeValue in
                switch routeValue {
                case .detail(let id):
                    if let word = words.first(where: { $0.id == id }) {
                        WordEntryDetailView(entry: word)
                    }
                }
            }
            .sheet(isPresented: $isAttributionPresented) {
                NavigationStack { AttributionView() }
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $activeImportSheet) { sheet in
                switch sheet {
                case .manual:
                    AddWordView(dictionary: dictionary) { outcome in
                        feedback = AddWordFeedback(outcome)
                    }
                    .presentationDetents([.medium, .large])
                case .image:
                    ImageImportView(dictionary: dictionary) { summary in
                        alertMessage = summary.message
                    }
                case .text:
                    TextImportView(dictionary: dictionary) { summary in
                        alertMessage = summary.message
                    }
                    .presentationDetents([.large])
                }
            }
            .alert("WordMem", isPresented: .init(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
            .alert("导入提示", isPresented: .init(
                get: { queueAttentionMessage != nil },
                set: { if !$0 { queueAttentionMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(queueAttentionMessage ?? "")
            }
            .overlay(alignment: .bottom) {
                if let feedback {
                    AddWordFeedbackView(feedback: feedback) {
                        withAnimation(.snappy) { self.feedback = nil }
                    }
                    .padding(.bottom, 18)
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation(.snappy) { self.feedback = nil }
                    }
                }
            }
            .task {
                queueAttentionMessage = await maintenance.processPendingSubmissions(in: modelContext)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("单词本还是空的", systemImage: "book.closed")
        } description: {
            Text("挑选权威词典收录的英文单词后保存；释义由 Open English WordNet 提供。")
        } actions: {
            Button("添加第一个单词") { activeImportSheet = .manual }
                .buttonStyle(.borderedProminent)
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

    private func deleteWords(at offsets: IndexSet) {
        let selected = offsets.map { words[$0] }
        do {
            try WordbookRepository(modelContext: modelContext).delete(selected)
        } catch {
            modelContext.rollback()
            alertMessage = "删除失败，请重试。"
        }
    }
}

private struct AddWordFeedbackView: View {
    let feedback: AddWordFeedback
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: feedback.isAdded ? "checkmark.circle.fill" : "checkmark.circle")
                .foregroundStyle(.green)
            Text(feedback.message)
            Button("好", action: dismiss)
        }
        .padding(12)
        .background(.regularMaterial, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

private struct WordRowView: View {
    let entry: WordEntry
    private enum DefinitionState {
        case loading
        case loaded(AuthoritativeDictionaryEntry)
        case unavailable
        case failed
    }

    @State private var dictionaryEntry: AuthoritativeDictionaryEntry?
    @State private var definitionState: DefinitionState = .loading

    private var definition: String {
        switch definitionState {
        case .loading: "正在加载权威释义"
        case .loaded(let dictionaryEntry): dictionaryEntry.primaryDefinition ?? "暂无释义"
        case .unavailable: "权威词典未收录"
        case .failed: "释义暂时无法加载"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.headword)
                    .font(.headline)

                if let partOfSpeech = dictionaryEntry?.primaryPartOfSpeech {
                    Text(partOfSpeech)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(definition)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if !entry.userTranslation.isEmpty {
                Text(entry.userTranslation)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .task(id: entry.normalizedKey) {
            do {
                let dictionaryEntry = try await WordNetKitAuthoritativeDictionaryProvider.shared
                    .entry(forTerm: entry.normalizedKey)
                if let dictionaryEntry {
                    self.dictionaryEntry = dictionaryEntry
                    definitionState = .loaded(dictionaryEntry)
                } else {
                    definitionState = .unavailable
                }
            } catch {
                definitionState = .failed
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct WordEntryDetailView: View {
    let entry: WordEntry
    @Query private var importContexts: [WordImportContext]
    @EnvironmentObject private var pronunciation: EnglishPronunciationPlayer
    @State private var authoritativeEntry: AuthoritativeDictionaryEntry?
    @State private var isLoadingDictionaryEntry = true

    private var contexts: [WordImportContext] {
        importContexts
            .filter { $0.entry?.id == entry.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.headword)
                        .font(.largeTitle.bold())
                    Text("规范词键：\(entry.normalizedKey)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("语言：\(entry.localeIdentifier)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if entry.originalText.localizedCaseInsensitiveCompare(entry.headword) != .orderedSame {
                    LabeledContent("输入", value: entry.originalText)
                }
                if !entry.userTranslation.isEmpty {
                    LabeledContent("我的翻译", value: entry.userTranslation)
                }
                if let example = entry.userExample, !example.isEmpty {
                    LabeledContent("我的例句", value: example)
                }
                if let note = entry.userNote, !note.isEmpty {
                    LabeledContent("我的笔记", value: note)
                }
            }

            Section("权威释义") {
                if isLoadingDictionaryEntry {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在加载 Open English WordNet 释义。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let dictionaryEntry = authoritativeEntry {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if let partOfSpeech = dictionaryEntry.primaryPartOfSpeech {
                                Text(partOfSpeech)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            if let ipa = dictionaryEntry.primaryIPA {
                                Text("/\(ipa)/")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }

                        ForEach(dictionaryEntry.senses.prefix(5)) { sense in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sense.definition)
                                    .font(.subheadline)
                                ForEach(Array(sense.examples.enumerated()), id: \.offset) { _, example in
                                    Text("“\(example)”")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    Text("权威词典未收录该词。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    AttributionView()
                } label: {
                    Label("Open English WordNet 授权", systemImage: "checkmark.seal")
                        .font(.footnote)
                }
            }

            if !contexts.isEmpty {
                Section("导入背景") {
                    ForEach(contexts) { context in
                        WordImportContextView(context: context)
                    }
                }
            }
        }
        .navigationTitle("单词详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            authoritativeEntry = try? await WordNetKitAuthoritativeDictionaryProvider.shared
                .entry(forTerm: entry.normalizedKey)
            isLoadingDictionaryEntry = false
        }
        .onDisappear { pronunciation.cancel() }
    }
}

private struct WordImportContextView: View {
    let context: WordImportContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(context.source.displayName, systemImage: context.source.systemImage)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(context.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let sourceText = context.sourceText, !sourceText.isEmpty {
                Text(sourceText)
                    .font(.subheadline)
                    .lineLimit(4)
            }

            if let note = context.metadata["userNote"], !note.isEmpty {
                Text("笔记：\(note)").font(.caption)
            }
            if let example = context.metadata["userExample"], !example.isEmpty {
                Text("例句：\(example)").font(.caption)
            }

            if let selected = context.selectedCandidate {
                Text("选择：\(selected)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let imageData = context.imageData, !imageData.isEmpty, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160)
                    .clipShape(.rect(cornerRadius: 10))
            }
        }
        .padding(.vertical, 3)
    }
}
