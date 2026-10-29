import SwiftUI

import UIKit

enum WordImportSheet: String, CaseIterable, Identifiable {
    case image
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .image: "图片导入"
        case .text: "文本导入"
        }
    }

    var systemImage: String {
        switch self {
        case .image: "photo.on.rectangle"
        case .text: "text.quote"
        }
    }
}

struct CameraImagePicker: UIViewControllerRepresentable {
    let completion: @MainActor (CameraCaptureResult) -> Void

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

    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
        UINavigationControllerDelegate
    {
        private let completion: @MainActor (CameraCaptureResult) -> Void

        init(completion: @MainActor @escaping (CameraCaptureResult) -> Void) {
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
                completion(CameraCaptureResult.resolve(image: image, jpegData: data))
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            Task { @MainActor in
                completion(.cancelled)
            }
        }
    }
}

enum CameraCaptureResult: Equatable {
    case success(Data)
    case cancelled
    case processingFailed

    static func resolve(image: UIImage?, jpegData: Data?) -> CameraCaptureResult {
        switch (image, jpegData) {
        case (.some, .some(let data)): .success(data)
        case (.none, _): .cancelled
        case (.some, .none): .processingFailed
        }
    }
}
