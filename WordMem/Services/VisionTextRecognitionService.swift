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
