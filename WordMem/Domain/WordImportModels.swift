import Foundation
import SwiftData

@Model
final class WordImportContext {
    var id: UUID
    var sourceRawValue: String
    var sourceText: String?
    var selectedCandidate: String?
    var recognizedText: String?
    @Attribute(.externalStorage) var imageData: Data?
    var submissionPayloadID: UUID?
    var candidatePayloadID: UUID?
    private var metadataData: Data
    var createdAt: Date
    @Relationship var entry: WordEntry?

    var source: WordImportSource {
        get { WordImportSource(rawValue: sourceRawValue) ?? .text }
        set { sourceRawValue = newValue.rawValue }
    }

    var metadata: [String: String] {
        get {
            guard !metadataData.isEmpty else { return [:] }
            return (try? JSONDecoder().decode([String: String].self, from: metadataData)) ?? [:]
        }
        set {
            metadataData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    init(
        id: UUID = UUID(),
        entry: WordEntry?,
        source: WordImportSource,
        sourceText: String? = nil,
        selectedCandidate: String? = nil,
        recognizedText: String? = nil,
        imageData: Data? = nil,
        submissionPayloadID: UUID? = nil,
        candidatePayloadID: UUID? = nil,
        metadata: [String: String] = [:],
        createdAt: Date = .now
    ) {
        self.id = id
        self.entry = entry
        self.sourceRawValue = source.rawValue
        self.sourceText = sourceText
        self.selectedCandidate = selectedCandidate
        self.recognizedText = recognizedText
        self.imageData = imageData
        self.submissionPayloadID = submissionPayloadID
        self.candidatePayloadID = candidatePayloadID
        self.metadataData = (try? JSONEncoder().encode(metadata)) ?? Data()
        self.createdAt = createdAt
    }
}

struct WordImportSummary: Equatable {
    let addedCount: Int
    let duplicateCount: Int

    var message: String {
        "已添加 \(addedCount) 个单词，已有 \(duplicateCount) 个单词。"
    }

    init(outcomes: [AddWordOutcome]) {
        addedCount = outcomes.filter(\.isAdded).count
        duplicateCount = outcomes.count - addedCount
    }
}
