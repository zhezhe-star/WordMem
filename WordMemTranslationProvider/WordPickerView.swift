import SwiftUI
import Translation

/// Word picker modeled after the reference experience:
/// selectable chips for the whole phrase and each word, then save.
struct WordPickerView: View {
    let sourceText: String
    let phraseTranslation: String
    let isPhraseTranslationReady: Bool
    let storage: LocalStorageManager
    let onCancel: () -> Void
    let onSave: () -> Void

    @State private var selected: Set<String> = []
    @State private var meanings: [String: String] = [:]
    @State private var configuration: TranslationSession.Configuration?
    @State private var isPreparingChips = true
    @State private var hasPreparedChips = false

    private var isPreparing: Bool {
        !isPhraseTranslationReady || isPreparingChips
    }

    private var chips: [String] {
        TranslationWordTokenizer.pickerChips(from: sourceText)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isPreparing {
                        loadingContent
                    } else {
                        selectionSummary
                        sourceSection
                        phraseTranslationSection
                        chipGrid
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: isPreparing)
        .translationTask(configuration) { session in
            await translateChips(with: session)
        }
        .onAppear {
            startChipTranslation()
        }
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
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay(Capsule().stroke(Color.green, lineWidth: 1))
                .foregroundStyle(.green)
            Spacer()
            Button("保存", action: save)
                .font(.body.weight(.semibold))
                .foregroundStyle(selected.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.green))
                .disabled(selected.isEmpty || isPreparing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var selectionSummary: some View {
        Text(selectionSummaryText)
            .font(.footnote)
            .foregroundStyle(.secondary)
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
        return "已保留整句，并拆出 \(wordCount) 个单词；选择后保存到 WordMem。"
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("原句")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(sourceText)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
        }
    }

    private var loadingContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ProgressView()
                Text("正在准备整句和单词…")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            sourceSection

            VStack(alignment: .leading, spacing: 6) {
                Text("整句翻译")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                ShimmerBox(height: 46)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("单词")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 10) {
                    ForEach(chips, id: \.self) { chip in
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

    private var phraseTranslationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("整句翻译")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(phraseTranslation.isEmpty ? "暂无整句翻译" : phraseTranslation)
                .font(.body)
                .foregroundStyle(phraseTranslation.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
        }
    }

    private var chipGrid: some View {
        FlowLayout(spacing: 10) {
            ForEach(chips, id: \.self) { chip in
                let isSelected = selected.contains(chip)
                Button {
                    if isSelected {
                        selected.remove(chip)
                    } else {
                        selected.insert(chip)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(chip)
                        if let meaning = meanings[chip], !meaning.isEmpty {
                            Text(meaning)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                        }
                    }
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isSelected ? Color.green.opacity(0.18) : Color(.secondarySystemGroupedBackground))
                    .overlay(
                        Capsule().stroke(isSelected ? Color.green : Color.clear, lineWidth: 1.5)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func startChipTranslation() {
        guard isPhraseTranslationReady, !hasPreparedChips else { return }
        hasPreparedChips = true
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
        for chip in chips where meanings[chip] == nil {
            if chip == TranslationWordTokenizer.normalizedPhrase(from: sourceText), !phraseTranslation.isEmpty {
                meanings[chip] = phraseTranslation
                continue
            }
            if let meaning = try? await session.translate(chip).targetText {
                meanings[chip] = meaning
            }
        }
        configuration = nil
        isPreparingChips = false
    }

    private func save() {
        let sourceOrder = chips.enumerated().reduce(into: [String: String]()) { result, item in
            result[item.element] = "\(item.offset)"
        }
        let candidates = selected.sorted().map { chip in
            let meaning = meanings[chip]
                ?? (chip == TranslationWordTokenizer.normalizedPhrase(from: sourceText) ? phraseTranslation : nil)
                ?? ""
            return WordImportCandidatePayload(
                text: chip,
                normalizedKey: chip.lowercased(),
                userTranslation: meaning.trimmingCharacters(in: .whitespacesAndNewlines),
                metadata: ["sourceOrder": sourceOrder[chip] ?? ""]
            )
        }
        let submission = WordImportSubmission(
            source: .translationProvider,
            sourceText: sourceText,
            recognizedText: sourceText,
            candidates: candidates,
            metadata: ["channel": "translation_provider"]
        )
        storage.appendSubmission(submission)
        onSave()
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

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
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
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
