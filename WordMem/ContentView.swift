import SwiftData
import SwiftUI

enum WordMemRoute: Hashable {
    case detail(UUID)
}

private enum DictionaryAvailability {
    case checking
    case available
    case unavailable
}

@MainActor
final class WordImportMaintenanceCoordinator {
    private var isRunning = false
    private let dictionary: any SystemDictionaryAuthorizing

    init(dictionary: any SystemDictionaryAuthorizing = UIKitSystemDictionaryAuthorizer()) {
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
    @State private var alertMessage: String?
    @State private var queueAttentionMessage: String?
    @State private var maintenance = WordImportMaintenanceCoordinator()
    @State private var dictionary = UIKitSystemDictionaryAuthorizer()

    var body: some View {
        NavigationStack(path: $route) {
            Group {
                if words.isEmpty { emptyState } else { wordList }
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
                        Label("导入单词", systemImage: "plus")
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
            .sheet(item: $activeImportSheet) { sheet in
                switch sheet {
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
            .task {
                queueAttentionMessage = await maintenance.processPendingSubmissions(in: modelContext)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("单词本还是空的", systemImage: "book.closed")
        } description: {
            Text("挑选系统词典收录的英文单词；翻译保存在本地元数据里。")
        } actions: {
            Button("导入第一个单词") { activeImportSheet = .text }
                .buttonStyle(.borderedProminent)
        }
    }

    private var wordList: some View {
        List {
            ForEach(words) { word in
                NavigationLink(value: WordMemRoute.detail(word.id)) {
                    WordListCard(entry: word)
                }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(
                        top: 6,
                        leading: WordMemDesign.margin,
                        bottom: 6,
                        trailing: WordMemDesign.margin
                    ))
            }
                .onDelete(perform: deleteWords)
        }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
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

struct WordEntryDetailView: View {
    let entry: WordEntry
    @Query private var importContexts: [WordImportContext]
    @EnvironmentObject private var pronunciation: EnglishPronunciationPlayer
    @State private var isSystemDictionaryPresented = false
    @State private var dictionaryAvailability: DictionaryAvailability = .checking

    private var contexts: [WordImportContext] {
        importContexts
            .filter { $0.entry?.id == entry.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WordDetailHeader(entry: entry, isSpeaking: pronunciation.isSpeaking) {
                    if pronunciation.isSpeaking {
                        pronunciation.cancel()
                    } else {
                        _ = pronunciation.play(entry.headword)
                    }
                }

                InfoMetaCard(title: "中文释义") {
                    Text(entry.translation.isEmpty ? "暂无本地翻译" : entry.translation)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                InfoMetaCard(title: "词条元数据") {
                    metaRow("输入原词", entry.originalText)
                    metaRow("规范词键", entry.normalizedKey)
                    metaRow("语言", entry.localeIdentifier)
                }

                if let example = entry.example, !example.isEmpty {
                    InfoMetaCard(title: "例句") {
                        Text(example)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let note = entry.note, !note.isEmpty {
                    InfoMetaCard(title: "笔记") {
                        Text(note)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                InfoMetaCard(title: "词典详情") {
                    Button {
                        isSystemDictionaryPresented = true
                    } label: {
                        HStack {
                            Label("在 Apple 词典中查看", systemImage: "character.book.closed")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: WordMemDesign.minimumTouchTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("systemDictionaryCard")
                    .accessibilityLabel("在 Apple 系统词典中查看 \(entry.normalizedKey)")

                    switch dictionaryAvailability {
                    case .checking:
                        Text("正在检查 Apple 本地词典收录状态。")
                    case .available:
                        Text("Apple 本地词典已收录该词。")
                    case .unavailable:
                        Text("Apple 本地词典未收录该词。")
                    }
                }

                if !contexts.isEmpty {
                    InfoMetaCard(title: "导入背景") {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(contexts) { context in
                                SourceEvidenceCard(context: context)
                            }
                        }
                    }
                }
            }
                .padding(.horizontal, WordMemDesign.margin)
                .padding(.top, 8)
                .padding(.bottom, 24)
        }
            .background(Color(.systemGroupedBackground))
        .navigationTitle("单词详情")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isSystemDictionaryPresented) {
            SystemDictionaryView(term: entry.normalizedKey)
        }
        .task {
            dictionaryAvailability = await UIKitSystemDictionaryAuthorizer()
                .hasDefinition(forTerm: entry.normalizedKey) ? .available : .unavailable
        }
        .onDisappear { pronunciation.cancel() }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)

            Text(value)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

struct SourceEvidenceCard: View {
    let context: WordImportContext

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Label(context.source.displayName, systemImage: context.source.systemImage)
                    .font(.caption.weight(.semibold))

                Spacer()

                Text(context.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let sourceText = displaySourceText {
                Text(sourceText)
                    .font(.body)
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let phraseTranslation = context.metadata["phraseTranslation"], !phraseTranslation.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("整段翻译")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(phraseTranslation)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))
            }

            if let selected = context.selectedCandidate {
                Text("选择：\(selected)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if let imageData = context.imageData,
               !imageData.isEmpty,
               let image = UIImage(data: imageData)
            {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 300)
                    .clipShape(.rect(cornerRadius: 14))
                    .accessibilityLabel("导入来源图片")
            }
        }
        .padding(WordMemDesign.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: WordMemDesign.cardRadius))
    }

    private var displaySourceText: String? {
        let text = context.sourceText ?? context.recognizedText
        return text?.isEmpty == false ? text : nil
    }
}
