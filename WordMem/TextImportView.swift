import SwiftData
import SwiftUI

struct TextImportView: View {
  let dictionary: any SystemDictionaryAuthorizing
  let completion: (WordImportSummary) -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @State private var model = DocumentImportReviewModel()
  @State private var draftText = ""
  @FocusState private var isSourceFocused: Bool

  #if DEBUG
    init(
      dictionary: any SystemDictionaryAuthorizing,
      completion: @escaping (WordImportSummary) -> Void,
      previewState: ImportPreviewState = ImportPreviewState()
    ) {
      self.dictionary = dictionary
      self.completion = completion
      _model = State(
        initialValue: DocumentImportReviewModel.preview(
          sourceText: previewState.sourceText,
          chips: previewState.chips,
          selectedOffsets: previewState.selectedOffsets
        )
      )
      _draftText = State(initialValue: previewState.sourceText)
    }
  #endif

  private var repository: WordbookRepository {
    WordbookRepository(modelContext: modelContext)
  }

  var body: some View {
    DocumentImportReviewScreen(
      model: model,
      title: "导入",
      subtitle: "输入英文内容，挑选要加入单词本的词。",
      onCancel: { dismiss() },
      onSubmit: { importSelectedWords() },
      showsHeader: false
    ) {
      if let reviewDocument = model.reviewDocument, model.phase.isReviewReady {
        ImportStructuredReviewCard(
          title: "原文",
          formattedText: CanonicalReviewProjection.formattedText(for: reviewDocument),
          onEditOriginal: { model.beginEditingOriginal() }
        )
      } else {
        ImportSourceEditorCard(
          title: "原文",
          placeholder: "输入或粘贴英文内容。",
          text: $draftText,
          isFocused: $isSourceFocused,
          onDismissKeyboard: { isSourceFocused = false }
        )
      }
    }
    .onChange(of: draftText) { _, newValue in
      let isEmpty = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      if isEmpty, !model.chips.isEmpty {
        model.reset()
      }
    }
    .onChange(of: model.phase) { _, newPhase in
      // Content is ready for review; stop letting the keyboard dominate it.
      if newPhase.isReviewReady {
        isSourceFocused = false
      }
    }
    .onChange(of: isSourceFocused) { wasFocused, isFocused in
      // Dismissing the keyboard is the explicit "done typing" action. It starts
      // preparation without adding another button or closing the sheet.
      guard wasFocused, !isFocused else { return }
      prepareDraftIfNeeded()
    }
  }

  private func prepareDraftIfNeeded() {
    let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, model.phase == .capturing else { return }
    Task { await model.prepareText(draftText) }
  }

  private func importSelectedWords() {
    guard model.canSubmit else { return }

    model.beginSaving()
    Task {
      defer { model.endSaving() }

      do {
        let submission = WordImportSubmission(
          source: .text,
          sourceText: model.preparedDisplayText,
          candidates: ImportCandidatePipeline.payloads(
            from: model.selection.selectedChips,
            translations: model.chipTranslations
          ),
          metadata: saveMetadata
        )
        let outcomes = try await repository.importSubmission(
          submission,
          using: dictionary
        )
        completion(WordImportSummary(outcomes: outcomes))
        dismiss()
      } catch {
        model.failSaving()
      }
    }
  }

  private var saveMetadata: [String: String] {
    var metadata = ["channel": WordImportSource.text.rawValue]
    if let translatedText = model.translatedText {
      metadata["phraseTranslation"] = translatedText
    }
    return metadata
  }
}

#if DEBUG
  #Preview("文本导入 · 空状态") {
    TextImportView(dictionary: UIKitSystemDictionaryAuthorizer()) { _ in }
  }

  #Preview("文本导入 · 正常候选") {
    TextImportView(
      dictionary: UIKitSystemDictionaryAuthorizer(),
      completion: { _ in },
      previewState: ImportPreviewState(
        sourceText: ImportPreviewFixtures.text(count: 8),
        chips: ImportPreviewFixtures.chips(count: 8),
        selectedOffsets: [1, 4]
      )
    )
  }

  #Preview("文本导入 · 55 个候选") {
    TextImportView(
      dictionary: UIKitSystemDictionaryAuthorizer(),
      completion: { _ in },
      previewState: ImportPreviewState(
        sourceText: ImportPreviewFixtures.text(count: 55),
        chips: ImportPreviewFixtures.chips(count: 55),
        selectedOffsets: [0, 27, 54]
      )
    )
  }
#endif
