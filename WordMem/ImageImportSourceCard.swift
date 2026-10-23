import PhotosUI
import SwiftUI
import UIKit

struct ImageImportSourceCard: View {
    let recognizedText: String
    let capturedImage: UIImage?
    let currentStep: ImportStep
    let isRecognizing: Bool
    let isSaving: Bool
    @Binding var photoItem: PhotosPickerItem?
    let presentCamera: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ImportContextCard(
                title: "图片原文",
                text: recognizedText.isEmpty ? "识别后在这里显示原文。" : recognizedText,
                thumbnail: capturedImage
            ) {
                accessory
            }

            if isRecognizing {
                recognitionState
            }
        }
    }

    @ViewBuilder
    private var accessory: some View {
        if currentStep == .content {
            sourceActions
        } else {
            Text("可重新选择图片")
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
            .tint(.blue)
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
