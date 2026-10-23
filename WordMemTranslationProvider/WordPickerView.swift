import SwiftUI
import Translation


/// Word picker modeled after the system Translation Provider card:
/// visible context, source-ordered chips, and explicit save.
struct WordPickerView: View {
    let sourceText: String
    let phraseTranslation: String
    let isPhraseTranslationReady: Bool
    let storage: any WordImportSubmissionStoring
    let onCancel: () -> Void
    let onSave: () -> Void

    @State private var selection = ImportChipSelection(chips: [])
    @State private var meanings: [String: String] = [:]
    @State private var configuration: TranslationSession.Configuration?
    @State private var isPreparingChips = true
    @State private var hasPreparedChips = false
    @State private var persistenceError: String?
    @State private var saveCoordinator = TranslationProviderSaveCoordinator()
    @State private var isPreparingSave = false

    private var isPreparing: Bool {
        !isPhraseTranslationReady || isPreparingChips
    }

    private var isSaving: Bool {
        saveCoordinator.isSaving || isPreparingSave
    }

    private var canSave: Bool {
        selection.selectedCount > 0 && !isPreparing && !isSaving
    }

    private var chips: [ImportCandidateChip] {
        let phrase = TranslationWordTokenizer.normalizedPhrase(from: sourceText)
        return TranslationWordTokenizer.pickerChips(from: sourceText)
            .enumerated()
            .map { offset, token in
                ImportCandidateChip(
                    id: token,
                    text: token,
                    sourceOrder: offset,
                    group: token == phrase ? "整句" : "单词"
                )
            }
    }

    private var sourceTokens: [String] {
        TranslationWordTokenizer.pickerChips(from: sourceText)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let persistenceError {
                        persistenceBanner(persistenceError)
                    }

                    if isPreparing {
                        loadingContent
                    } else {
                        contextSection
                        selectionSection
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            ImportPrimaryCTA(
                title: isSaving ? "正在保存…" : "保存 \(selection.selectedCount) 个",
                isLoading: isSaving,
                action: save
            )
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .background(.bar)
            .disabled(!canSave)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .animation(.easeInOut(duration: 0.28), value: isPreparing)
        .translationTask(configuration) { session in
            await translateChips(with: session)
        }
        .onAppear(perform: startChipTranslation)
        .onChange(of: isPhraseTranslationReady) { _, isReady in
            if isReady {
                startChipTranslation()
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button("取消", action: onCancel)
                .font(.body.weight(.semibold))

            Spacer()

            Text("英文")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.blue.opacity(0.11), in: .capsule)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func persistenceBanner(_ message: String) -> some View {
        Label(message, systemImage: "externaldrive.badge.exclamationmark")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.orange)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(message)
    }

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ImportStepHeader(
                currentStep: .selection,
                title: "挑选单词",
                subtitle: selectionSummaryText
            )

            ImportContextCard(
                title: "原句",
                text: sourceText
            ) {
                phraseTranslationAccessory
            }
        }
    }

    private var phraseTranslationAccessory: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("整句翻译")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(phraseTranslation.isEmpty ? "暂无整句翻译" : phraseTranslation)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(phraseTranslation.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
    }

    private var selectionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ImportSelectionToolbar(
                selectedCount: selection.selectedCount,
                totalCount: chips.count,
                onSelectAll: { selection.selectAll() },
                onClear: { selection.clear() }
            )

            ImportCandidateChipGrid(
                chips: chips,
                selection: $selection,
                meanings: meanings
            )
        }
    }

    private var selectionSummaryText: String {
        let phrase = TranslationWordTokenizer.normalizedPhrase(from: sourceText)
        let wordCount = TranslationWordTokenizer.wordChips(from: sourceText).count
        if phrase.isEmpty && wordCount == 0 {
            return "这句话没有可保存的内容。"
        }
        if wordCount == 0 {
            return "已保留整句，可选择后保存到 WordMem。"
        }
        return "已保留整句，并拆出 \(wordCount) 个单词。"
    }

    private var loadingContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ProgressView()
                Text("正在准备整句和单词…")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ImportContextCard(title: "原句", text: sourceText) {
                ShimmerBox(height: 46)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                Text("单词")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 10) {
                    ForEach(sourceTokens, id: \.self) { chip in
                        HStack(spacing: 8) {
                            Text(chip)
                            ShimmerBox(width: 38, height: 12, capsule: true)
                        }
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func startChipTranslation() {
        guard isPhraseTranslationReady, !hasPreparedChips else { return }
        hasPreparedChips = true
        selection = ImportChipSelection(chips: chips)

        guard !chips.isEmpty else {
            isPreparingChips = false
            return
        }
        configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "zh-Hans")
        )
    }

    private func translateChips(with session: TranslationSession) async {
        for chip in chips where meanings[chip.id] == nil {
            if chip.id == TranslationWordTokenizer.normalizedPhrase(from: sourceText),
                !phraseTranslation.isEmpty
            {
                meanings[chip.id] = phraseTranslation
                continue
            }
            if let meaning = try? await session.translate(chip.text).targetText {
                meanings[chip.id] = meaning
            }
        }
        configuration = nil
        isPreparingChips = false
    }

    private func save() {
        guard canSave else { return }
        isPreparingSave = true

        Task { @MainActor in
            // Let SwiftUI render the disabled/saving button before file I/O.
            await Task.yield()
            let builder = TranslationProviderSubmissionBuilder(
                sourceText: sourceText,
                phraseTranslation: phraseTranslation,
                selectedChips: Set(selection.selectedChips.map(\.id)),
                meanings: meanings
            )
            let submission = builder.makeSubmission()

            let result = saveCoordinator.save(
                submission,
                storage: storage,
                onSaved: onSave
            )

            if case .completed(let error) = result {
                persistenceError = error
            }
            isPreparingSave = false
        }
    }

}

private struct ShimmerBox: View {
    var width: CGFloat?
    var height: CGFloat
    var capsule = false

    @State private var isAnimating = false

    var body: some View {
        RoundedRectangle(cornerRadius: capsule ? 8 : 12)
            .fill(Color(.tertiarySystemFill))
            .frame(width: width, height: height)
            .modifier(ShimmerEffect(isAnimating: isAnimating))
            .onAppear {
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

private struct ShimmerEffect: ViewModifier {
    let isAnimating: Bool

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { proxy in
                LinearGradient(
                    colors: [.clear, .white.opacity(0.55), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: max(28, proxy.size.width * 0.7))
                .offset(x: isAnimating ? proxy.size.width * 1.1 : -proxy.size.width * 0.8)
            }
            .mask(content)
        }
    }
}
