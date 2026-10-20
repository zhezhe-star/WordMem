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

extension AddWordFeedback: Equatable {
    static func == (lhs: AddWordFeedback, rhs: AddWordFeedback) -> Bool {
        lhs.id == rhs.id
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WordEntry.updatedAt, order: .reverse) private var words: [WordEntry]
    @State private var route: [WordMemRoute] = []
    @State private var isAddWordPresented = false
    @State private var feedback: AddWordFeedback?
    @State private var alertMessage: String?

    @State private var dictionaryService: any DictionaryLookupService = BareWordDictionaryLookupService()

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
                    Button {
                        isAddWordPresented = true
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
            .sheet(isPresented: $isAddWordPresented) {
                AddWordView(dictionaryService: dictionaryService) { outcome in
                    presentFeedback(for: outcome)
                }
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
            }
            .alert("添加失败", isPresented: .init(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
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
            .task {
                initializeDictionaryService()
                migrateLegacyWordbook()
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
                isAddWordPresented = true
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
        entries.forEach(modelContext.delete)

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            alertMessage = "删除失败，请重试。"
        }
    }

    private func migrateLegacyWordbook() {
        do {
            try LegacyWordbookMigrator.migrateIfNeeded(defaults: .standard, into: modelContext)
        } catch {
            alertMessage = "旧单词本迁移失败。WordMem 已保留原始数据。"
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
        case .notFound: .secondary
        }
    }
}

struct WordEntryDetailView: View {
    let entry: WordEntry
    @State private var synthesizer = AVSpeechSynthesizer()

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

                    if entry.originalInput.localizedCaseInsensitiveCompare(entry.headword) != .orderedSame {
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
                    Text("本地词典暂未收录。")
                        .foregroundStyle(.secondary)
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
                       entry.userTranslation != entry.translation {
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

            if entry.hasLegacyUserData {
                Section("旧记录") {
                    if let sentence = entry.legacyExampleSentence, !sentence.isEmpty {
                        Text(sentence)

                        if let translated = entry.legacyTranslatedExampleSentence,
                           !translated.isEmpty {
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

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
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
