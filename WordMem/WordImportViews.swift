import PhotosUI
import SwiftData
import SwiftUI
import UIKit

enum WordImportSheet: String, CaseIterable, Identifiable {
    case manual
    case image
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: "手动添加"
        case .image: "图片导入"
        case .text: "文本导入"
        }
    }

    var systemImage: String {
        switch self {
        case .manual: "square.and.pencil"
        case .image: "photo.on.rectangle"
        case .text: "text.quote"
        }
    }
}

struct TextImportView: View {
    let dictionaryService: any DictionaryLookupService
    let completion: (WordImportSummary) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var sourceText = ""
    @State private var candidates: [WordImportCandidate] = []
    @State private var selectedKeys: Set<String> = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var repository: WordbookRepository {
        WordbookRepository(modelContext: modelContext)
    }

    private var selectedWords: [String] {
        candidates
            .filter { selectedKeys.contains($0.normalizedKey) }
            .map(\.text)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("输入单词或英文句子，选择要加入单词本的词。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $sourceText)
                    .frame(minHeight: 108)
                    .padding(10)
                    .overlay(alignment: .topLeading) {
                        if sourceText.isEmpty {
                            Text("例如：The quick brown fox jumps over the lazy dog.")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.quaternary)
                    }
                    .onChange(of: sourceText, initial: true) {
                        refreshCandidates()
                    }

                if candidates.isEmpty {
                    ContentUnavailableView(
                        "还没有候选词",
                        systemImage: "text.magnifyingglass",
                        description: Text("输入英文内容后，这里会显示可选择单词。")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    WordCandidateListView(
                        candidates: candidates,
                        selectedKeys: $selectedKeys
                    )
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button(action: importSelectedWords) {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isSaving ? "正在导入" : "导入 \(selectedWords.count) 个单词")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(selectedWords.isEmpty || isSaving)
            }
            .padding(20)
            .background(Color(.systemBackground))
            .navigationTitle("文本导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
            }
        }
    }

    private func refreshCandidates() {
        candidates = EnglishWordCandidateSplitter.candidates(from: sourceText)
        selectedKeys = Set(candidates.map(\.normalizedKey))
    }

    private func importSelectedWords() {
        guard !selectedWords.isEmpty, !isSaving else { return }

        isSaving = true
        errorMessage = nil

        Task {
            defer { isSaving = false }

            do {
                let outcomes = try await repository.importWords(
                    selectedWords,
                    source: .text,
                    sourceText: sourceText,
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

struct ImageImportView: View {
    let dictionaryService: any DictionaryLookupService
    let completion: (WordImportSummary) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var photoItem: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var imageData: Data?
    @State private var recognizedText = ""
    @State private var candidates: [WordImportCandidate] = []
    @State private var selectedKeys: Set<String> = []
    @State private var isRecognizing = false
    @State private var isSaving = false
    @State private var isCameraPresented = false
    @State private var errorMessage: String?

    private let recognitionService: any TextRecognitionService = VisionTextRecognitionService()
    private var isCameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    private var repository: WordbookRepository {
        WordbookRepository(modelContext: modelContext)
    }

    private var selectedWords: [String] {
        candidates
            .filter { selectedKeys.contains($0.normalizedKey) }
            .map(\.text)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    PhotosPicker(
                        selection: $photoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("从相册选择", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)

                    Button {
                        isCameraPresented = true
                    } label: {
                        Label("拍照", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .disabled(!isCameraAvailable || isRecognizing || isSaving)
                }

                if let capturedImage {
                    Image(uiImage: capturedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 190)
                        .frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: 14))
                } else {
                    ContentUnavailableView(
                        "选择包含英文的图片",
                        systemImage: "doc.text.viewfinder",
                        description: Text("WordMem 会在本机识别文字，再让你选择要记的单词。")
                    )
                    .frame(maxHeight: .infinity)
                }

                if isRecognizing {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在识别图片文字")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !candidates.isEmpty {
                    WordCandidateListView(
                        candidates: candidates,
                        selectedKeys: $selectedKeys
                    )
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button(action: importSelectedWords) {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isSaving ? "正在导入" : "导入 \(selectedWords.count) 个单词")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(selectedWords.isEmpty || isRecognizing || isSaving)
            }
            .padding(20)
            .background(Color(.systemBackground))
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
            .sheet(isPresented: $isCameraPresented) {
                CameraImagePicker { data in
                    Task { await processImageData(data) }
                }
                .ignoresSafeArea()
            }
        }
    }

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item else { return }

        do {
            let data = try await item.loadTransferable(type: Data.self)
            await processImageData(data)
        } catch {
            errorMessage = "无法读取所选图片，请更换图片后重试。"
        }
    }

    private func processImageData(_ data: Data?) async {
        guard let data, let image = UIImage(data: data), !data.isEmpty else {
            errorMessage = "无法读取所选图片，请更换图片后重试。"
            return
        }

        let preparedData = image.jpegData(compressionQuality: 0.85) ?? data
        imageData = preparedData
        capturedImage = image
        isRecognizing = true
        errorMessage = nil

        defer { isRecognizing = false }

        do {
            let lines = try await recognitionService.recognizeText(in: preparedData)
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw WordImageImportError.noRecognizedText }

            recognizedText = text
            candidates = EnglishWordCandidateSplitter.candidates(from: text)
            selectedKeys = Set(candidates.map(\.normalizedKey))

            if candidates.isEmpty {
                throw WordImageImportError.noRecognizedText
            }
        } catch {
            recognizedText = ""
            candidates = []
            selectedKeys = []
            errorMessage = (error as? WordImageImportError)?.errorDescription ?? "文字识别失败，请重试。"
        }
    }

    private func importSelectedWords() {
        guard let imageData, !selectedWords.isEmpty, !isSaving else { return }

        isSaving = true
        errorMessage = nil

        Task {
            defer { isSaving = false }

            do {
                let outcomes = try await repository.importWords(
                    selectedWords,
                    source: .image,
                    sourceText: recognizedText,
                    imageData: imageData,
                    recognizedText: recognizedText,
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

struct CameraImagePicker: UIViewControllerRepresentable {
    let completion: @MainActor (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let completion: @MainActor (Data?) -> Void

        init(completion: @MainActor @escaping (Data?) -> Void) {
            self.completion = completion
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            let data = image?.jpegData(compressionQuality: 0.85)
            picker.dismiss(animated: true)
            Task { @MainActor in
                completion(data)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            Task { @MainActor in
                completion(nil)
            }
        }
    }
}

private struct WordCandidateListView: View {
    let candidates: [WordImportCandidate]
    @Binding var selectedKeys: Set<String>

    var body: some View {
        List(candidates) { candidate in
            Button {
                if selectedKeys.contains(candidate.normalizedKey) {
                    selectedKeys.remove(candidate.normalizedKey)
                } else {
                    selectedKeys.insert(candidate.normalizedKey)
                }
            } label: {
                HStack {
                    Text(candidate.text)
                        .font(.body)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: selectedKeys.contains(candidate.normalizedKey) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(.tint)
                }
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        }
        .listStyle(.insetGrouped)
        .clipShape(.rect(cornerRadius: 12))
        .scrollBounceBehavior(.basedOnSize)
    }
}
