import SwiftUI
import Translation

/// Word picker modeled after the reference experience:
/// selectable chips for the whole phrase and each word, then save.
struct WordPickerView: View {
    let sourceText: String
    let phraseTranslation: String
    let storage: LocalStorageManager
    let onCancel: () -> Void
    let onSave: () -> Void

    @State private var selected: Set<String> = []
    @State private var meanings: [String: String] = [:]
    @State private var configuration: TranslationSession.Configuration?

    private var chips: [String] {
        var values: [String] = []
        if !sourceText.isEmpty { values.append(sourceText) }
        let words = sourceText
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && $0.range(of: "[a-zA-Z]", options: .regularExpression) != nil }
        for word in words where !values.contains(word) {
            values.append(word)
        }
        return values
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    selectionSummary
                    sourceSection
                    chipGrid
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .translationTask(configuration) { session in
            await translateChips(with: session)
        }
        .onAppear {
            startChipTranslation()
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
                .disabled(selected.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var selectionSummary: some View {
        Text("已选 \(selected.count) 个，保存后加入 WordMem 单词本。")
            .font(.footnote)
            .foregroundStyle(.secondary)
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
        configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "zh-Hans")
        )
    }

    private func translateChips(with session: TranslationSession) async {
        for chip in chips where meanings[chip] == nil {
            if let meaning = try? await session.translate(chip).targetText {
                meanings[chip] = meaning
            }
        }
        configuration = nil
    }

    private func save() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        for chip in selected.sorted() {
            let meaning = meanings[chip]
                ?? (chip == sourceText ? phraseTranslation : nil)
                ?? ""
            let word = WordData(
                word: chip,
                translation: meaning.trimmingCharacters(in: .whitespacesAndNewlines),
                createDateString: formatter.string(from: Date())
            )
            storage.addWord(word)
        }
        onSave()
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
