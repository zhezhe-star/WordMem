import PhotosUI
import SwiftUI
import UIKit

struct ImageImportSourceCard: View {
    let sourceText: String
    let capturedImage: UIImage?
    let currentStep: ImportStep
    let isRecognizing: Bool
    let isSaving: Bool
    @Binding var photoItem: PhotosPickerItem?
    let presentCamera: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let capturedImage {
                imagePreview(sourceText, capturedImage)
            } else {
                emptyPreview
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.regularMaterial, in: .rect(cornerRadius: 22))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
                    }
            }

            if isRecognizing {
                recognitionState
            }
        }
    }

    private func imagePreview(_ sourceText: String, _ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ImportSourceTextCard(title: "图片原文", text: sourceText) {
                EmptyView()
            }

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel("所选原始图片")

            if currentStep == .content {
                sourceActions
            } else {
                reselectionActions
            }
        }
    }

    private var emptyPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("原始图片", systemImage: "photo")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("选择或拍摄一张图片，WordMem 会在本机识别英文候选词。")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            sourceActions
        }
    }

    private var reselectionActions: some View {
        HStack(spacing: 8) {
            PhotosPicker(
                selection: $photoItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label("更换照片", systemImage: "photo")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isRecognizing || isSaving)

            Button(action: presentCamera) {
                Label("重拍", systemImage: "camera")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(WordMemDesign.accent)
            .disabled(isRecognizing || isSaving)
        }
    }

    private var sourceActions: some View {
        HStack(spacing: 10) {
            PhotosPicker(
                selection: $photoItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label("从相册选择", systemImage: "photo")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isRecognizing || isSaving)

            Button(action: presentCamera) {
                Label("拍照", systemImage: "camera")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(WordMemDesign.accent)
            .disabled(isRecognizing || isSaving)
        }
    }

    private var recognitionState: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text("正在识别图片文字")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在识别图片文字")
        .accessibilityAddTraits(.updatesFrequently)
    }
}
