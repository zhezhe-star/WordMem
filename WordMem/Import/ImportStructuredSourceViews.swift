import SwiftUI

/// Read-only canonical projection shown once import preparation succeeds.
/// The explicit edit affordance returns typed text to the original editor.
struct ImportStructuredReviewCard: View {
  let title: String
  let formattedText: String
  let onEditOriginal: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .center) {
        Text(title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        Spacer()

        if let onEditOriginal {
          Button("编辑原文", action: onEditOriginal)
            .font(.footnote.weight(.semibold))
            .tint(WordMemDesign.accent)
        }
      }

      Text(formattedText)
        .font(.body.weight(.medium))
        .monospaced()
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color(.secondarySystemGroupedBackground),
      in: .rect(cornerRadius: WordMemDesign.cardRadius)
    )
    .accessibilityElement(children: .contain)
  }
}
