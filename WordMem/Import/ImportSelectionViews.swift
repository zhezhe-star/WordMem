import SwiftUI
import UIKit

struct ImportCandidateChipGrid: View {
  let chips: [ImportCandidateChip]
  @Binding var selection: ImportChipSelection
  var meanings: [String: String] = [:]
  var isTranslating = false
  var onRestoreOriginal: ((ImportCandidateChip) -> Void)? = nil
  @State private var sections: [ImportCandidateSection] = []

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      ForEach(sections) { section in
        sectionView(section)
      }
    }
    .onChange(of: chips, initial: true) {
      sections = ImportCandidateOrganizer.sections(
        from: ImportCandidateChip.uniquelyIdentified(chips)
      )
    }
  }

  @ViewBuilder
  private func sectionView(_ section: ImportCandidateSection) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      if let title = section.title {
        Text(title)
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.secondary)
          .accessibilityAddTraits(.isHeader)
      }

      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 168), spacing: WordMemDesign.cardSpacing)],
        spacing: WordMemDesign.cardSpacing
      ) {
        ForEach(section.chips) { chip in
          ImportCandidateChipButton(
            chip: chip,
            isSelected: selection.isSelected(chip.id),
            meaning: meanings[chip.id],
            isTranslating: isTranslating,
            onRestoreOriginal: onRestoreOriginal
          ) {
            selection.toggle(chip.id)
          }
        }
      }
    }
  }
}

private struct ImportCandidateChipButton: View {
  let chip: ImportCandidateChip
  let isSelected: Bool
  let meaning: String?
  let isTranslating: Bool
  let onRestoreOriginal: ((ImportCandidateChip) -> Void)?
  let action: () -> Void

  private var labelColor: Color {
    isSelected ? WordMemDesign.accent : .primary
  }

  private var detailColor: AnyShapeStyle {
    isSelected ? AnyShapeStyle(WordMemDesign.accent.opacity(0.86)) : AnyShapeStyle(.secondary)
  }

  private var backgroundShape: AnyShapeStyle {
    isSelected
      ? AnyShapeStyle(WordMemDesign.accent.opacity(0.12))
      : AnyShapeStyle(Color(.secondarySystemGroupedBackground))
  }

  private var strokeColor: Color {
    isSelected ? WordMemDesign.accent.opacity(0.48) : Color(uiColor: .separator).opacity(0.32)
  }

  private var iconColor: AnyShapeStyle {
    isSelected ? AnyShapeStyle(WordMemDesign.accent) : AnyShapeStyle(.tertiary)
  }

  var body: some View {
    if chip.isImportable {
      Button(action: action) {
        chipLabel
      }
      .buttonStyle(.plain)
      .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isSelected)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(accessibilityLabel)
      .accessibilityHint("连按切换选择状态")
      .accessibilityValue(isSelected ? "已选择" : "未选择")
      .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    } else if chip.canRestoreOriginal {
      HStack(spacing: 6) {
        chipLabel

        Button {
          if let onRestoreOriginal {
            onRestoreOriginal(chip)
          }
        } label: {
          Text("还原原拼写")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.13), in: .capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.orange)
        .accessibilityLabel("还原原拼写 \(chip.advice?.originalText ?? chip.text)")
      }
      .padding(.vertical, 3)
    }
  }

  private var chipLabel: some View {
    HStack(alignment: .center, spacing: 10) {
      Capsule()
        .fill(isSelected ? WordMemDesign.accent : Color(uiColor: .separator).opacity(0.4))
        .frame(width: 3, height: 38)

      VStack(alignment: .leading, spacing: 5) {
        Text(chip.text)
          .font(.callout.weight(isSelected ? .semibold : .medium))
          .foregroundStyle(labelColor)
          .lineLimit(1)

        Text(translationText)
          .font(.caption)
          .foregroundStyle(detailColor)
          .lineLimit(2)

        if chip.lemmaBadgeText != nil || chip.spellingBadgeText != nil || chip.availabilityBadgeText != nil {
          HStack(spacing: 5) {
            if let lemmaText = chip.lemmaBadgeText {
              adviceBadge(lemmaText, color: .indigo)
            }
            if let spellingText = chip.spellingBadgeText {
              adviceBadge(spellingText, color: .orange)
            }
            if let availabilityText = chip.availabilityBadgeText {
              adviceBadge(availabilityText, color: .red)
            }
          }
        }
      }

      Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        .font(.footnote)
        .foregroundStyle(iconColor)
    }
    .padding(12)
    .background(backgroundShape, in: .rect(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .strokeBorder(strokeColor, lineWidth: isSelected ? 1.2 : 0.8)
    }
    .frame(maxWidth: .infinity, minHeight: WordMemDesign.minimumTouchTarget, alignment: .leading)
    .contentShape(.rect(cornerRadius: 14))
  }

  private var translationText: String {
    if let meaning, !meaning.isEmpty { return meaning }
    return isTranslating ? "翻译中…" : "暂无翻译"
  }

  private var accessibilityLabel: String {
    var label = ImportCandidateAccessibility.label(text: chip.text, meaning: meaning)
    if let lemmaText = chip.lemmaBadgeText { label += "，\(lemmaText)" }
    if let spellingText = chip.spellingBadgeText { label += "，\(spellingText)" }
    if let availabilityText = chip.availabilityBadgeText { label += "，\(availabilityText)" }
    return label
  }

  private func adviceBadge(_ text: String, color: Color) -> some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(color)
      .padding(.horizontal, 6)
      .padding(.vertical, 3)
      .background(color.opacity(0.11), in: .capsule)
      .lineLimit(1)
  }
}

struct ImportSelectionToolbar: View {
  let selectedCount: Int
  let totalCount: Int
  let onSelectAll: () -> Void
  let onClear: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Text("已选 \(selectedCount)/\(totalCount)")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)

      Spacer()

      Button("全选", action: onSelectAll)
        .font(.footnote.weight(.semibold))
        .disabled(selectedCount == totalCount)

      Button("清除", action: onClear)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
        .disabled(selectedCount == 0)
    }
    .buttonStyle(.plain)
    .tint(.blue)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("候选词选择")
    .accessibilityValue("已选择 \(selectedCount) 个，共 \(totalCount) 个")
  }
}

struct ImportPrimaryCTA: View {
  let title: String
  let isLoading: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if isLoading {
          ProgressView()
            .controlSize(.small)
            .tint(.white)
        } else {
          Image(systemName: "square.and.arrow.down")
        }

        Text(title)
          .font(.body.weight(.semibold))
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 15)
    }
    .buttonStyle(.borderedProminent)
    .tint(WordMemDesign.accent)
    .disabled(isLoading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(isLoading ? "正在保存" : "未在保存")
    .accessibilityAddTraits(.isButton)
  }
}

#if DEBUG
  struct ImportPreviewState {
    var word = ""
    var sourceText = ""
    var recognizedText = ""
    var chips: [ImportCandidateChip] = []
    var selectedOffsets: Set<Int> = []
    var thumbnail: UIImage?
  }

  enum ImportPreviewFixtures {
    static func chips(count: Int) -> [ImportCandidateChip] {
      let letters = Array("abcdefghijklmnopqrstuvwxyz")
      return (0..<count).map { index in
        let text = "\(letters[index / 26])\(letters[index % 26])"
        return ImportCandidateChip(
          id: text,
          text: text,
          sourceOrder: index
        )
      }
    }

    static func text(count: Int) -> String {
      chips(count: count).map(\.text).joined(separator: " ")
    }

    static func thumbnail() -> UIImage {
      UIGraphicsImageRenderer(size: CGSize(width: 132, height: 132)).image { context in
        UIColor.systemBlue.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 132, height: 132))
        UIColor.white.setFill()
        context.fill(CGRect(x: 18, y: 36, width: 96, height: 12))
        context.fill(CGRect(x: 18, y: 66, width: 72, height: 12))
        context.fill(CGRect(x: 18, y: 96, width: 84, height: 12))
      }
    }

    static func selection(
      for chips: [ImportCandidateChip],
      selectedOffsets: Set<Int>
    ) -> ImportChipSelection {
      var selection = ImportChipSelection(chips: chips)
      for offset in Array(selectedOffsets).sorted() where chips.indices.contains(offset) {
        selection.toggle(chips[offset].id)
      }
      return selection
    }
  }
#endif
