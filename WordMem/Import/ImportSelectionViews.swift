import SwiftUI
import UIKit

struct ImportCandidateChipGrid: View {
  let chips: [ImportCandidateChip]
  @Binding var selection: ImportChipSelection
  var meanings: [String: String] = [:]
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
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .accessibilityAddTraits(.isHeader)
      }

      FlowLayout(spacing: 9) {
        ForEach(section.chips) { chip in
          ImportCandidateChipButton(
            chip: chip,
            isSelected: selection.isSelected(chip.id),
            meaning: meanings[chip.id]
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
  let action: () -> Void

  private var detailText: String? {
    guard let meaning, !meaning.isEmpty else { return nil }
    return meaning
  }

  private var labelColor: Color {
    isSelected ? .blue : .primary
  }

  private var detailColor: AnyShapeStyle {
    isSelected ? AnyShapeStyle(Color.blue.opacity(0.82)) : AnyShapeStyle(.secondary)
  }

  private var backgroundShape: AnyShapeStyle {
    isSelected
      ? AnyShapeStyle(Color.blue.opacity(0.13))
      : AnyShapeStyle(Color(.secondarySystemBackground))
  }

  private var strokeColor: Color {
    isSelected ? .blue.opacity(0.5) : Color(uiColor: .separator).opacity(0.5)
  }

  private var iconColor: AnyShapeStyle {
    isSelected ? AnyShapeStyle(Color.blue) : AnyShapeStyle(.tertiary)
  }

  var body: some View {
    Button(action: action) {
      chipLabel
    }
    .buttonStyle(.plain)
    .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isSelected)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(ImportCandidateAccessibility.label(text: chip.text, meaning: meaning))
    .accessibilityHint("连按切换选择状态")
    .accessibilityValue(isSelected ? "已选择" : "未选择")
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }

  private var chipLabel: some View {
    HStack(spacing: 6) {
      Text(chip.text)
        .font(.callout.weight(isSelected ? .semibold : .regular))
        .lineLimit(1)

      if let detailText {
        Text(detailText)
          .font(.caption2)
          .foregroundStyle(detailColor)
          .lineLimit(1)
      }

      Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        .font(.footnote)
        .foregroundStyle(iconColor)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
    .foregroundStyle(labelColor)
    .background(backgroundShape, in: .capsule)
    .overlay {
      Capsule()
        .strokeBorder(strokeColor, lineWidth: 1)
    }
    .contentShape(.capsule)
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
    .tint(.blue)
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
    var deselectedOffsets: Set<Int> = []
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
      deselectedOffsets: Set<Int>
    ) -> ImportChipSelection {
      var selection = ImportChipSelection(chips: chips)
      for offset in Array(deselectedOffsets).sorted() where chips.indices.contains(offset) {
        selection.toggle(chips[offset].id)
      }
      return selection
    }
  }
#endif
