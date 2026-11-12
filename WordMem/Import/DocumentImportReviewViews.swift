import SwiftUI
import UIKit

/// The single adaptive import screen shared by text and image import. It shows
/// one compact source area, an optional translation card, candidate chips, and
/// one primary action; pipeline details never appear.
struct DocumentImportReviewScreen<Source: View>: View {
  @Bindable var model: DocumentImportReviewModel
  let title: String
  let subtitle: String
  let onCancel: () -> Void
  let onSubmit: () -> Void
  var showsHeader = true
  var noWordsActionTitle = "编辑原文"
  @ViewBuilder var source: () -> Source

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            if showsHeader {
              header
            } else if !model.phase.isReviewReady {
              compactHeader
            }

            source()

            if let session = model.documentSession, session.phase != .idle {
              ImportDocumentTranslationCard(session: session)
            }

            if model.isBusy {
              ImportCandidateSkeletonGrid()
            }

            if let statusMessage = model.reviewStatusMessage,
              model.phase != .noWordsAvailable
            {
              ImportInlineStatusView(
                text: statusMessage,
                isError: model.errorMessage != nil,
                showsProgress: model.phase == .organizing || model.phase == .preparingWords
              )
            }

            if model.phase == .reviewing {
              reviewContent
            } else if model.phase == .noWordsAvailable {
              ImportNoWordsEmptyState(
                actionTitle: noWordsActionTitle,
                onAction: { model.beginEditingOriginal() }
              )
            }
          }
          .padding(20)
          .padding(.bottom, 8)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)

        bottomBar
      }
      .background(Color(.systemGroupedBackground).ignoresSafeArea())
      .interactiveDismissDisabled(model.isBusy || model.isSaving)
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(action: onCancel) {
            Text("取消")
              .font(.subheadline.weight(.medium))
              .padding(.horizontal, 14)
              .padding(.vertical, 6)
              .background(Color(uiColor: .tertiarySystemFill), in: .capsule)
          }
          .buttonStyle(.plain)
          .disabled(model.isSaving)
        }
      }
      .importCandidateTranslations(
        chips: model.chips,
        sourceText: nil,
        configuration: $model.chipTranslationConfiguration,
        translations: $model.chipTranslations,
        phraseTranslation: .constant(nil),
        isTranslating: $model.isChipTranslating,
        phase: $model.chipTranslationPhase
      )
      .importDocumentTranslationTask(for: model.documentSession)
      .onChange(of: model.phase) { _, newPhase in
        announceReviewReadiness(newPhase)
      }
      .onChange(of: model.errorMessage) { _, message in
        if let message {
          UIAccessibility.post(notification: .announcement, argument: message)
        }
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title)
        .font(.largeTitle.bold())
        .lineLimit(1)
        .minimumScaleFactor(0.85)

      Text(subtitle)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }

  private var compactHeader: some View {
    Text(subtitle)
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder
  private var bottomBar: some View {
    if model.phase.isReviewReady, !model.offeredChips.isEmpty {
      ImportPrimaryCTA(
        title: DocumentImportStatusPresenter.primaryButtonTitle(
          selectedCount: model.selectedWords.count,
          isSaving: model.isSaving
        ),
        isLoading: model.isSaving,
        action: onSubmit
      )
      .disabled(!model.canSubmit)
      .padding(.horizontal, 20)
      .padding(.top, 10)
      .padding(.bottom, 14)
      .background(.bar)
    }
  }

  private var reviewContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      if model.didUseDeterministicFallback {
        Text("已为你准备词典候选。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      ImportSelectionToolbar(
        selectedCount: model.selection.selectedCount,
        totalCount: model.offeredChips.count,
        onSelectAll: { model.selectAllWords() },
        onClear: { model.clearSelection() }
      )

      ImportCandidateChipGrid(
        chips: model.offeredChips,
        selection: Binding(
          get: { model.selection },
          set: { model.replaceSelection($0) }
        ),
        meanings: model.chipTranslations,
        isTranslating: model.isChipTranslating,
        onRestoreOriginal: { model.restoreOriginal($0) }
      )
    }
  }

  private func announceReviewReadiness(_ phase: DocumentImportReviewPhase) {
    let announcement: String?
    switch phase {
    case .reviewing:
      announcement = "内容已准备好，请选择要保存的单词。"
    case .noWordsAvailable:
      announcement = DocumentImportStatusPresenter.noWordsMessage
    case .curatorUnavailable:
      announcement = DocumentImportStatusPresenter.curatorUnavailableMessage
    case .capturing, .organizing, .preparingWords:
      announcement = nil
    }
    if let announcement {
      UIAccessibility.post(notification: .announcement, argument: announcement)
    }
  }
}

/// Placeholder cards shown while the candidate pipeline is running, so the
/// screen never collapses to a spinner-only blank state.
struct ImportCandidateSkeletonGrid: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("待选单词")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)

      VStack(spacing: WordMemDesign.cardSpacing) {
        ForEach(0..<4, id: \.self) { _ in
          HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 9) {
              RoundedRectangle(cornerRadius: 4)
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 72, height: 15)
              RoundedRectangle(cornerRadius: 4)
                .fill(Color(uiColor: .quaternarySystemFill))
                .frame(width: 48, height: 11)
            }
            Spacer(minLength: 12)
            Circle()
              .fill(Color(uiColor: .tertiarySystemFill))
              .frame(width: 20, height: 20)
          }
          .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
          .padding(WordMemDesign.cardPadding)
          .background(
            Color(.secondarySystemGroupedBackground),
            in: .rect(cornerRadius: WordMemDesign.cardRadius)
          )
        }
      }
    }
    .accessibilityHidden(true)
  }
}

/// Calm, actionable empty state for the no-candidates outcome.
struct ImportNoWordsEmptyState: View {
  let actionTitle: String
  let onAction: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "text.magnifyingglass")
        .font(.system(size: 30, weight: .regular))
        .foregroundStyle(.tertiary)
        .frame(width: 64, height: 64)
        .background(Color(uiColor: .tertiarySystemFill), in: .circle)

      VStack(spacing: 6) {
        Text("没有可保存的单词")
          .font(.headline)
        Text("可以换一段内容后再整理。")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }

      Button(action: onAction) {
        Text(actionTitle)
          .font(.subheadline.weight(.semibold))
          .padding(.horizontal, 18)
          .padding(.vertical, 10)
      }
      .buttonStyle(.borderedProminent)
      .tint(WordMemDesign.accent)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 20)
    .accessibilityElement(children: .contain)
  }
}

/// Optional enrichment card fed by the canonical document translation session.
/// Its failure states stay actionable and never block word selection.
struct ImportDocumentTranslationCard: View {
  let session: ImportDocumentSession

  @State private var expansion = ImportContextExpansion(text: "")

  private var translatedText: String {
    let blocks = session.translatedDocument?.blocks ?? []
    return blocks.map(\.text).joined(separator: "\n")
  }

  private var languagePairLabel: String {
    let sourceCode =
      session.document.detectedLanguage?.languageCode?.identifier.uppercased() ?? "EN"
    let targetCode = session.targetLanguage.languageCode?.identifier ?? "zh"
    let targetLabel = targetCode == "zh" ? "中文" : targetCode.uppercased()
    return "\(sourceCode) → \(targetLabel)"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(languagePairLabel)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color(uiColor: .tertiarySystemFill), in: .capsule)
        .accessibilityLabel("英语到中文")

      VStack(alignment: .leading, spacing: 10) {
        content
      }
      .padding(16)
      .background(
        Color(.secondarySystemGroupedBackground),
        in: .rect(cornerRadius: WordMemDesign.cardRadius)
      )
    }
    .onChange(of: translatedText) { _, text in
      expansion = ImportContextExpansion(text: text)
    }
  }

  @ViewBuilder
  private var content: some View {
    if let statusMessage = DocumentImportStatusPresenter.translationStatus(for: session.phase) {
      statusMessageView(statusMessage)
    } else if session.phase == .completed {
      translatedContent
    } else {
      EmptyView()
    }
  }

  private func statusMessageView(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(message)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
        .accessibilityAddTraits(.updatesFrequently)

      if showsRetry {
        Button("重试") { session.retry() }
          .font(.footnote.weight(.semibold))
      }
    }
  }

  private var showsRetry: Bool {
    switch session.phase {
    case .needsLanguageDownload, .unsupportedLanguagePair, .failed:
      true
    default:
      false
    }
  }

  @ViewBuilder
  private var translatedContent: some View {
    Text(translatedText)
      .font(.body.weight(.medium))
      .lineLimit(expansion.lineLimit)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)

    if expansion.isExpandable {
      Button {
        withAnimation(.snappy) { expansion.toggle() }
      } label: {
        Label(
          expansion.isExpanded ? "收起" : "显示全部",
          systemImage: expansion.isExpanded ? "chevron.up" : "chevron.down"
        )
        .font(.footnote.weight(.semibold))
      }
      .buttonStyle(.plain)
      .tint(WordMemDesign.accent)
    }
  }
}

/// The single inline status area replacing technical progress rows.
struct ImportInlineStatusView: View {
  let text: String
  var isError = false
  var showsProgress = true

  var body: some View {
    HStack(spacing: 10) {
      if isError {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
      } else if showsProgress {
        ProgressView()
          .controlSize(.small)
      }

      // Terminal states (for example "no words" or "curation unavailable")
      // must still render their actionable copy without a spinner. Only the
      // leading progress indicator is conditional.
      if !text.isEmpty {
        Text(text)
          .font(isError ? .footnote.weight(.medium) : .subheadline)
          .foregroundStyle(isError ? Color.red : Color.secondary)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(text)
    .accessibilityAddTraits(.updatesFrequently)
  }
}

extension View {
  /// Watches the active document translation session, tolerating the nil
  /// window before a document exists.
  @ViewBuilder
  func importDocumentTranslationTask(for session: ImportDocumentSession?) -> some View {
    if let session {
      importDocumentTranslationTask(for: session)
    } else {
      self
    }
  }
}
