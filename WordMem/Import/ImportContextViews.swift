import SwiftUI
import UIKit

enum ImportStep: Int, CaseIterable {
    case content
    case selection

    var title: String {
        switch self {
        case .content: "添加内容"
        case .selection: "挑选单词"
        }
    }
}

struct ImportStepHeader: View {
    let currentStep: ImportStep
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.largeTitle.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                stepItem(ImportStep.content)
                connector(isActive: currentStep == .selection)
                stepItem(ImportStep.selection)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("导入步骤，添加内容和挑选单词")
        .accessibilityValue("当前是\(currentStep.title)")
    }

    private func stepItem(_ step: ImportStep) -> some View {
        let isCurrent = step == currentStep

        return HStack(spacing: 6) {
            Text("\(step.rawValue + 1)")
                .font(.caption2.weight(.bold))
                .frame(width: 21, height: 21)
                .background(isCurrent ? Color.blue : Color(.tertiarySystemFill))
                .foregroundStyle(isCurrent ? .white : .secondary)
                .clipShape(Circle())

            Text(step.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isCurrent ? Color.blue : .secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(isCurrent ? Color.blue.opacity(0.11) : Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }

    private func connector(isActive: Bool) -> some View {
        Rectangle()
            .fill(isActive ? Color.blue.opacity(0.55) : Color(.separator))
            .frame(height: 1.5)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

struct ImportContextCard<Accessory: View>: View {
    let title: String
    let text: String
    var thumbnail: UIImage?
    var isContextHidden = false
    @ViewBuilder var accessory: () -> Accessory

    @State private var expansion: ImportContextExpansion

    init(
        title: String,
        text: String,
        thumbnail: UIImage? = nil,
        isContextHidden: Bool = false,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.title = title
        self.text = text
        self.thumbnail = thumbnail
        self.isContextHidden = isContextHidden
        self.accessory = accessory
        _expansion = State(initialValue: ImportContextExpansion(text: text))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 5) {
                Image(systemName: "text.quote")
                    .font(.caption.weight(.bold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 14) {
                Text(text)
                    .font(.body.weight(.medium))
                    .lineLimit(expansion.lineLimit)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 66, height: 66)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
                        }
                        .accessibilityLabel("所选图片")
                }
            }

            accessory()

            if expansion.isExpandable {
                Button {
                    withAnimation(.snappy) {
                        expansion.toggle()
                    }
                } label: {
                    Label(
                        expansion.isExpanded ? "收起" : "显示全部",
                        systemImage: expansion.isExpanded ? "chevron.up" : "chevron.down"
                    )
                    .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .tint(.blue)
                .accessibilityLabel(expansion.isExpanded ? "收起原文" : "显示全部原文")
                .accessibilityValue(expansion.isExpanded ? "已展开" : "已折叠")
                .accessibilityAddTraits(.isButton)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
        }
        .accessibilityHidden(isContextHidden)
        .onChange(of: text, initial: true) {
            expansion = ImportContextExpansion(text: text)
        }
    }
}

struct ImportPhraseTranslationCard: View {
    let translation: String?
    let isTranslating: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("整段翻译", systemImage: "text.badge.checkmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if isTranslating {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在翻译原文…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let translation, !translation.isEmpty {
                Text(translation)
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("整段翻译暂不可用")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

struct ImportSourceEditorCard: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .font(.body)
                .frame(minHeight: 94)
                .accessibilityLabel(title)
                .accessibilityHint("输入英文内容后挑选单词")
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
        }
    }
}

struct ImportErrorMessage: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.red)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(message)
            .accessibilityAddTraits(.updatesFrequently)
    }
}
