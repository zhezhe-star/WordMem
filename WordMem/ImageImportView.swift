import PhotosUI

import SwiftData

import SwiftUI

import UIKit

struct ImageImportView: View {
    let dictionaryService: any DictionaryLookupService
    let completion: (WordImportSummary) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var photoItem: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var imageData: Data?
    @State private var recognizedText = ""
    @State private var chips: [ImportCandidateChip] = []
    @State private var selection = ImportChipSelection(chips: [])
    @State private var isRecognizing = false
    @State private var isSaving = false
    @State private var isCameraPresented = false
    @State private var cameraAvailability: CameraAvailability = .notDetermined
    @State private var cameraFallbackMessage: String?
    @State private var errorMessage: String?

    private let recognitionService: any TextRecognitionService = VisionTextRecognitionService()
    private let processingCoordinator = WordImageProcessingCoordinator()

    private var repository: WordbookRepository {
        WordbookRepository(modelContext: modelContext)
    }

    private var selectedWords: [String] {
        selection.selectedChips.map(\.text)
    }

    private var currentStep: ImportStep {
        chips.isEmpty ? .content : .selection
    }

    private var hasImage: Bool {
        capturedImage != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ImportStepHeader(
                            currentStep: currentStep,
                            title: "图片导入",
                            subtitle: hasImage ? "确认原文后，挑选要记的单词。" : "选择图片，本机识别英文后挑选单词。"
                        )

                        ImageImportSourceCard(
                            recognizedText: recognizedText,
                            capturedImage: capturedImage,
                            currentStep: currentStep,
                            isRecognizing: isRecognizing,
                            isSaving: isSaving,
                            photoItem: $photoItem,
                            presentCamera: presentCameraIfAvailable
                        )

                        if !chips.isEmpty {
                            selectionContent
                        }

                        if let errorMessage {
                            ImportErrorMessage(message: errorMessage)
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)

                ImportPrimaryCTA(
                    title: isSaving ? "正在导入" : "导入 \(selectedWords.count) 个单词",
                    isLoading: isSaving,
                    action: importSelectedWords
                )
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 14)
                .background(.bar)
                .disabled(selectedWords.isEmpty || isRecognizing || isSaving)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("图片导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
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
                        errorMessage = "无法保存拍摄的照片，请重试。"
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    private var selectionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ImportSelectionToolbar(
                selectedCount: selection.selectedCount,
                totalCount: chips.count,
                onSelectAll: { selection.selectAll() },
                onClear: { selection.clear() }
            )

            ImportCandidateChipGrid(chips: chips, selection: $selection)
        }
    }

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item else { return }

        let token = processingCoordinator.begin()
        isRecognizing = true
        defer {
            if processingCoordinator.finish(token) {
                isRecognizing = false
            }
        }

        do {
            let data = try await item.loadTransferable(type: Data.self)
            guard processingCoordinator.shouldCommit(token) else { return }
            await processImageData(data, inheritedToken: token)
        } catch {
            guard !Task.isCancelled, processingCoordinator.shouldCommit(token) else { return }
            errorMessage = "无法读取所选图片，请更换图片后重试。"
        }
    }

    private func processImageData(_ data: Data?, inheritedToken token: UUID? = nil) async {
        // When loading supplies a token, the load phase already owns processing state.
        let ownsProcessing: Bool
        let activeToken: UUID
        if let token {
            ownsProcessing = false
            activeToken = token
        } else {
            ownsProcessing = true
            activeToken = processingCoordinator.begin()
        }
        defer {
            if ownsProcessing, processingCoordinator.finish(activeToken) {
                isRecognizing = false
            }
        }

        guard let data, let image = UIImage(data: data), !data.isEmpty else {
            guard processingCoordinator.shouldCommit(activeToken) else { return }
            errorMessage = "无法读取所选图片，请更换图片后重试。"
            return
        }

        guard processingCoordinator.shouldCommit(activeToken) else { return }
        let preparedData = WordImagePreparer.prepare(data) ?? data
        imageData = preparedData
        capturedImage = image

        if processingCoordinator.shouldCommit(activeToken) {
            errorMessage = nil
        }

        do {
            let lines = try await recognitionService.recognizeText(in: preparedData)
            guard processingCoordinator.shouldCommit(activeToken) else { return }
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw WordImageImportError.noRecognizedText }

            let refreshedCandidates = EnglishWordCandidateSplitter.candidates(from: text)
            guard !refreshedCandidates.isEmpty else { throw WordImageImportError.noRecognizedText }

            recognizedText = text
            chips = ImportCandidateAdapter.chips(from: refreshedCandidates)
            selection = ImportChipSelection(chips: chips)

        } catch {
            guard processingCoordinator.shouldCommit(activeToken) else { return }
            guard !Task.isCancelled else { return }
            recognizedText = ""
            chips = []
            selection = ImportChipSelection(chips: [])
            errorMessage = (error as? WordImageImportError)?.errorDescription ?? "文字识别失败，请重试。"
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
        guard let imageData, !selectedWords.isEmpty, !isSaving else { return }

        isSaving = true
        errorMessage = nil

        Task {
            defer { isSaving = false }

            do {
                let submission = WordImportSubmission(
                    source: .image,
                    sourceText: recognizedText,
                    recognizedText: recognizedText,
                    imageData: imageData,
                    candidates: selectedWords.map {
                        WordImportCandidatePayload(
                            text: $0,
                            normalizedKey: WordInputNormalizer.normalizedKey(from: $0)
                        )
                    },
                    metadata: [
                        "channel": WordImportSource.image.rawValue,
                        "imageByteCount": "\(imageData.count)",
                    ]
                )
                let outcomes = try await repository.importSubmission(
                    submission,
                    using: dictionaryService
                )
                completion(WordImportSummary(outcomes: outcomes))
                dismiss()
            } catch {
                errorMessage = "批量导入失败，请重试。"
            }
        }
    }
}

#Preview("图片导入") {
    ImageImportView(dictionaryService: BareWordDictionaryLookupService()) { _ in }
}

