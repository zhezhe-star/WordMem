import SwiftUI

enum WordMemDesign {
    static let margin: CGFloat = 16
    static let cardSpacing: CGFloat = 12
    static let cardPadding: CGFloat = 16
    static let cardRadius: CGFloat = 18
    static let minimumTouchTarget: CGFloat = 44

    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.68, green: 0.79, blue: 0.57, alpha: 1)
            : UIColor(red: 0.29, green: 0.46, blue: 0.26, alpha: 1)
    })
}

struct LanguageBadge: View {
    var body: some View {
        Text("EN")
            .font(.caption2.monospaced().weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 7))
            .accessibilityLabel("英语")
    }
}

struct WordListCard: View {
    let entry: WordEntry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Capsule()
                .fill(WordMemDesign.accent)
                .frame(width: 4, height: 58)

            VStack(alignment: .leading, spacing: 7) {
                Text(entry.headword)
                    .font(.title3.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    LanguageBadge()

                    Text(phoneticText)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 12)

                    Text("待学习")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Text(entry.translation.isEmpty ? "暂无本地翻译" : entry.translation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(WordMemDesign.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: WordMemDesign.cardRadius))
        .accessibilityElement(children: .combine)
    }

    private var phoneticText: String {
        guard let phonetic = entry.phonetic?.trimmingCharacters(in: .whitespacesAndNewlines),
              !phonetic.isEmpty
        else { return "暂无音标" }
        return phonetic.hasPrefix("/") ? phonetic : "/\(phonetic)/"
    }
}

struct WordDetailHeader: View {
    let entry: WordEntry
    let isSpeaking: Bool
    let onPlayPronunciation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(entry.headword)
                .font(.largeTitle.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.55)

            HStack(spacing: 12) {
                LanguageBadge()

                Text(phoneticText)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Button(action: onPlayPronunciation) {
                    Image(systemName: isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                        .font(.title3)
                        .foregroundStyle(isSpeaking ? WordMemDesign.accent : Color.primary)
                        .frame(width: WordMemDesign.minimumTouchTarget, height: WordMemDesign.minimumTouchTarget)
                        .background(Color(uiColor: .tertiarySystemFill), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSpeaking ? "停止发音" : "播放发音")
                .accessibilityValue(entry.headword)
            }
        }
    }

    private var phoneticText: String {
        guard let phonetic = entry.phonetic?.trimmingCharacters(in: .whitespacesAndNewlines),
              !phonetic.isEmpty
        else { return "暂无音标" }
        return phonetic.hasPrefix("/") ? phonetic : "/\(phonetic)/"
    }
}

struct InfoMetaCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WordMemDesign.cardPadding)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: WordMemDesign.cardRadius))
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
