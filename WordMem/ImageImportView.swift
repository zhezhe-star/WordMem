import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ImageImportView: View {
  let dictionary: any SystemDictionaryAuthorizing
  let completion: (WordImportSummary) -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @State private var model = DocumentImportReviewModel()
  @State private var photoItem: PhotosPickerItem?
  @State private var capturedImage: UIImage?
  @State private var imageData: Data?
  @State private var isCameraPresented = false
  @State private var cameraAvailability: CameraAvailability = .notDetermined
  @State private var cameraFallbackMessage: String?

  private let recognitionService: any ImageDocumentRecognitionService = VisionDocumentReader()
  private let processingCoordinator = WordImageProcessingCoordinator()

  #if DEBUG
    init(
      dictionary: any SystemDictionaryAuthorizing,
      completion: @escaping (WordImportSummary) -> Void,
      previewState: ImportPreviewState = ImportPreviewState()
    ) {
      self.dictionary = dictionary
      self.completion = completion
      _capturedImage = State(initialValue: previewState.thumbnail)
      _imageData = State(initialValue: previewState.thumbnail?.jpegData(compressionQuality: 0.9))
      _model = State(
        initialValue: DocumentImportReviewModel.preview(
          sourceText: previewState.recognizedText,
          chips: previewState.chips,
          selectedOffsets: previewState.selectedOffsets
        )
      )
    }
  #endif

  private var repository: WordbookRepository {
    WordbookRepository(modelContext: modelContext)
  }

  private var hasImage: Bool {
    capturedImage != nil
  }

  var body: some View {
    DocumentImportReviewScreen(
      model: model,
      title: "导入",
      subtitle: hasImage ? "确认原图后，挑选要加入单词本的词。" : "选择图片，挑选要加入单词本的词。",
      onCancel: { dismiss() },
      onSubmit: { importSelectedWords() }
    ) {
      ImageImportSourceCard(
        sourceText: model.preparedDisplayText,
        capturedImage: capturedImage,
        isProcessing: model.isBusy,
        isSaving: model.isSaving,
        photoItem: $photoItem,
        presentCamera: presentCameraIfAvailable
      )
    }
    .task(id: photoItem) {
      await loadImage(from: photoItem)
    }
    .task {
      cameraAvailability = CameraAvailability.current()
    }
    .onReceive(
      NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
    ) { _ in
      cameraAvailability = CameraAvailability.current()
    }
    .alert(
      "无法使用相机",
      isPresented: .init(
        get: { cameraFallbackMessage != nil },
        set: { if !$0 { cameraFallbackMessage = nil } }
      )
    ) {
      Button("好", role: .cancel) {}
    } message: {
      Text(cameraFallbackMessage ?? cameraAvailability.fallbackMessage)
    }
    .sheet(isPresented: $isCameraPresented) {
      CameraImagePicker { data in
        switch data {
        case .success(let data):
          Task { await processImageData(data) }
        case .cancelled:
          break
        case .processingFailed:
          model.failProcessing(with: WordImageImportError.invalidImageData)
        }
      }
      .ignoresSafeArea()
    }
  }

  private func loadImage(from item: PhotosPickerItem?) async {
    guard let item else { return }

    let token = processingCoordinator.begin()
    model.beginImageProcessing()
    defer {
      _ = processingCoordinator.finish(token)
    }

    do {
      let data = try await item.loadTransferable(type: Data.self)
      guard processingCoordinator.shouldCommit(token) else { return }
      await processImageData(data, inheritedToken: token)
    } catch {
      guard !Task.isCancelled, processingCoordinator.shouldCommit(token) else { return }
      model.failProcessing(with: WordImageImportError.invalidImageData)
    }
  }

  private func processImageData(_ data: Data?, inheritedToken token: UUID? = nil) async {
    let ownsProcessing: Bool
    let activeToken: UUID
    if let token {
      ownsProcessing = false
      activeToken = token
    } else {
      ownsProcessing = true
      activeToken = processingCoordinator.begin()
      model.beginImageProcessing()
    }
    defer {
      if ownsProcessing {
        _ = processingCoordinator.finish(activeToken)
      }
    }

    do {
      guard let data, let image = UIImage(data: data), !data.isEmpty else {
        throw WordImageImportError.invalidImageData
      }
      guard processingCoordinator.shouldCommit(activeToken) else { return }

      let preparedData = WordImagePreparer.prepare(data) ?? data
      imageData = preparedData
      capturedImage = image

      let document = try await recognitionService.recognizeDocument(in: preparedData)
      guard processingCoordinator.shouldCommit(activeToken) else { return }

      let rawText = Self.displayText(from: document)
      let text = OCRTextFormatter.formattedText(from: rawText)
      guard !text.isEmpty else {
        throw WordImageImportError.noRecognizedText
      }

      await model.prepareImageDocument(document, displayText: text)
    } catch {
      guard processingCoordinator.shouldCommit(activeToken) else { return }
      guard !Task.isCancelled else { return }
      model.failProcessing(with: error)
    }
  }

  private func presentCameraIfAvailable() {
    let availability = CameraAvailability.current()
    cameraAvailability = availability

    if availability.canOpenCamera {
      isCameraPresented = true
    } else {
      cameraFallbackMessage = availability.fallbackMessage
    }
  }

  private func importSelectedWords() {
    guard model.canSubmit, let imageData else { return }

    model.beginSaving()
    Task {
      defer { model.endSaving() }

      do {
        let submission = WordImportSubmission(
          source: .image,
          sourceText: model.preparedDisplayText,
          recognizedText: model.preparedDisplayText,
          imageData: imageData,
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
    var metadata = [
      "channel": WordImportSource.image.rawValue,
      "imageByteCount": "\(imageData?.count ?? 0)",
    ]
    if let translatedText = model.translatedText {
      metadata["phraseTranslation"] = translatedText
    }
    return metadata
  }

  /// Canonical blocks stay untouched; this only projects structured source
  /// text into the compact review format shown by image import.
  private static func displayText(from document: CanonicalDocument) -> String {
    document.blocks
      .filter { $0.kind != .list && $0.kind != .table }
      .map(\.text)
      .joined(separator: "\n")
  }
}

#if DEBUG
  #Preview("图片导入 · 空状态") {
    ImageImportView(dictionary: UIKitSystemDictionaryAuthorizer()) { _ in }
  }

  #Preview("图片导入 · 正常候选") {
    ImageImportView(
      dictionary: UIKitSystemDictionaryAuthorizer(),
      completion: { _ in },
      previewState: ImportPreviewState(
        recognizedText: "Beautiful mountain views appear after the morning rain.",
        chips: ImportPreviewFixtures.chips(count: 8),
        selectedOffsets: [2],
        thumbnail: ImportPreviewFixtures.thumbnail()
      )
    )
  }

  #Preview("图片导入 · 55 个候选") {
    ImageImportView(
      dictionary: UIKitSystemDictionaryAuthorizer(),
      completion: { _ in },
      previewState: ImportPreviewState(
        recognizedText: String(repeating: "Beautiful mountain views appear after rain. ", count: 8),
        chips: ImportPreviewFixtures.chips(count: 55),
        selectedOffsets: [0, 27, 54],
        thumbnail: ImportPreviewFixtures.thumbnail()
      )
    )
  }
#endif
