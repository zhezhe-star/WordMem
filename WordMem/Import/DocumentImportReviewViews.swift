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

            if let statusMessage = model.reviewStatusMessage {
              ImportInlineStatusView(
                text: statusMessage,
                isError: model.errorMessage != nil,
                showsProgress: model.phase == .organizing || model.phase == .preparingWords
              )
            }

            if model.phase == .reviewing {
              reviewContent
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
          Button("取消") { onCancel() }
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

/// Optional enrichment card fed by the canonical document translation session.
/// Its failure states stay actionable and never block word selection.
struct ImportDocumentTranslationCard: View {
  let session: ImportDocumentSession

  @State private var expansion = ImportContextExpansion(text: "")

  private var translatedText: String {
    let blocks = session.translatedDocument?.blocks ?? []
    return blocks.map(\.text).joined(separator: "\n")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("译文", systemImage: "text.badge.checkmark")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      content
    }
    .padding(16)
    .background(
      Color(.secondarySystemGroupedBackground),
      in: .rect(cornerRadius: WordMemDesign.cardRadius)
    )
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
