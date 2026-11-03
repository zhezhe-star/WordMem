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
    @State private var advisorChips: [ImportCandidateChip] = []
    @State private var advisorToken = UUID()
    @State private var meanings: [String: String] = [:]
    @State private var configuration: TranslationSession.Configuration?
    @State private var isPreparingChips = true
    @State private var hasPreparedChips = false
    @State private var persistenceError: String?
    @State private var saveCoordinator = TranslationProviderSaveCoordinator()
    @State private var isPreparingSave = false
    @State private var hasSavedSubmission = false
    @State private var isWaitingForExtensionClose = false

    private var isPreparing: Bool {
        !isPhraseTranslationReady || isPreparingChips
    }

    private var isSaving: Bool {
        saveCoordinator.isSaving || isPreparingSave || isWaitingForExtensionClose
    }

    private var canSave: Bool {
        selection.selectedCount > 0 && !isPreparing && !isSaving && !hasSavedSubmission
    }

    private var sourceTokens: [String] {
        TranslationWordTokenizer.wordChips(from: sourceText)
    }

    private var offeredChips: [ImportCandidateChip] {
        advisorChips.filter(\.isOffered)
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
                title: hasSavedSubmission
                    ? "已保存"
                    : (isSaving ? "正在保存…" : "保存 \(selection.selectedCount) 个"),
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
            Button(action: onCancel) {
                Text("取消")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WordMemDesign.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(WordMemDesign.accent.opacity(0.11), in: .capsule)
            }
            .buttonStyle(.plain)
            .tint(WordMemDesign.accent)
                .frame(
                    minWidth: WordMemDesign.minimumTouchTarget,
                    minHeight: WordMemDesign.minimumTouchTarget,
                    alignment: .leading
                )

            Spacer()

            Text("英文")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WordMemDesign.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(WordMemDesign.accent.opacity(0.11), in: .capsule)
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
                totalCount: offeredChips.count,
                onSelectAll: { selection.selectAll() },
                onClear: { selection.clear() }
            )

            ImportCandidateChipGrid(
                chips: offeredChips,
                selection: $selection,
                meanings: meanings,
                onRestoreOriginal: restoreOriginal
            )
        }
    }

    private var selectionSummaryText: String {
        let wordCount = TranslationWordTokenizer.wordChips(from: sourceText).count
        if wordCount == 0 {
            return "这句话没有可保存的内容。"
        }
        return "已保留原句，并拆出 \(wordCount) 个可选单词。"
    }

    private var loadingContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ProgressView()
                Text("正在准备单词…")
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
        let token = UUID()
        advisorToken = token

        Task {
            let preparedChips = await ImportCandidatePipeline.translationChips(from: sourceText)
            guard advisorToken == token else { return }
            advisorChips = preparedChips
            selection = ImportChipSelection(chips: preparedChips)
            guard !preparedChips.isEmpty else {
                isPreparingChips = false
                return
            }
            configuration = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: "zh-Hans")
            )
        }
    }

    private func restoreOriginal(_ chip: ImportCandidateChip) {
        let restored = chip.restoringOriginal()
        advisorChips = advisorChips.map { $0.id == chip.id ? restored : $0 }
        selection.updateChips(advisorChips)
    }

    private func translateChips(with session: TranslationSession) async {
        for chip in advisorChips where meanings[chip.id] == nil {
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
                meanings: meanings,
                advisedChips: advisorChips
            )
            let submission = builder.makeSubmission()

            let result = saveCoordinator.save(
                submission,
                storage: storage,
                onSaved: {}
            )

            if case .completed(nil) = result {
                await Task.yield()
                hasSavedSubmission = true
                isPreparingSave = false
                isWaitingForExtensionClose = true
                onSave()
                scheduleCloseFallback()
                return
            }
            if case .completed(let error?) = result {
                persistenceError = error
            }
            isPreparingSave = false
        }
    }

    private func scheduleCloseFallback() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            isWaitingForExtensionClose = false
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
