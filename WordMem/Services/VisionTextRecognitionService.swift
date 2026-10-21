import AVFoundation
import UIKit
import Vision

protocol TextRecognitionService: Sendable {
    func recognizeText(in imageData: Data) async throws -> [String]
}

actor VisionTextRecognitionService: TextRecognitionService {
    func recognizeText(in imageData: Data) async throws -> [String] {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            throw WordImageImportError.invalidImageData
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        return (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first?.string
        }
    }
}

enum WordImagePreparer {
    static func prepare(
        _ data: Data,
        maxPixelDimension: CGFloat = 1_600,
        compressionQuality: CGFloat = 0.72
    ) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let pixelSize = CGSize(
            width: max(image.size.width * max(image.scale, 1), 1),
            height: max(image.size.height * max(image.scale, 1), 1)
        )
        let longestPixelDimension = max(pixelSize.width, pixelSize.height)
        let scale = min(1, maxPixelDimension / longestPixelDimension)
        let targetSize = CGSize(
            width: max((pixelSize.width * scale).rounded(), 1),
            height: max((pixelSize.height * scale).rounded(), 1)
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resizedImage = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return resizedImage.jpegData(compressionQuality: compressionQuality)
            ?? image.jpegData(compressionQuality: compressionQuality)
            ?? data
    }
}

@MainActor
final class WordImageProcessingCoordinator {
    private(set) var isProcessing = false
    private var latestToken = UUID()

    func begin() -> UUID {
        latestToken = UUID()
        isProcessing = true
        return latestToken
    }

    func shouldCommit(_ token: UUID) -> Bool {
        token == latestToken && isProcessing
    }

    func finish(_ token: UUID) -> Bool {
        guard shouldCommit(token) else { return false }
        isProcessing = false
        return true
    }
}

enum CameraAvailability: Equatable {
    case ready
    case notDetermined
    case denied
    case restricted
    case unavailable

    static func status(
        isSourceTypeAvailable: Bool,
        authorization: AVAuthorizationStatus
    ) -> CameraAvailability {
        guard isSourceTypeAvailable else { return .unavailable }

        switch authorization {
        case .authorized: return .ready
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .unavailable
        }
    }

    @MainActor
    static func current() -> CameraAvailability {
        status(
            isSourceTypeAvailable: UIImagePickerController.isSourceTypeAvailable(.camera),
            authorization: AVCaptureDevice.authorizationStatus(for: .video)
        )
    }

    var canOpenCamera: Bool {
        self == .ready || self == .notDetermined
    }

    var fallbackMessage: String {
        switch self {
        case .ready, .notDetermined:
            ""
        case .denied:
            "相机权限已关闭。请在系统设置中允许 WordMem 使用相机，也可以从相册选择图片。"
        case .restricted:
            "相机权限受到限制。请调整系统设置，或从相册选择包含英文的图片。"
        case .unavailable:
            "此设备没有可用相机，可以从相册选择包含英文的图片。"
        }
    }
}

enum WordImageImportError: LocalizedError {
    case invalidImageData
    case noRecognizedText

    var errorDescription: String? {
        switch self {
        case .invalidImageData: "无法读取所选图片，请更换图片后重试。"
        case .noRecognizedText: "未在图片中识别到英文单词。"
        }
    }
}
