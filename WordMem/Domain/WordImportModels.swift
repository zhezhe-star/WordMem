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
    var entryID: UUID?
    var submissionPayloadID: UUID?
    var candidatePayloadID: UUID?
    var payloadSchemaVersion: Int?
    private var metadataData: Data
    var createdAt: Date
    @Relationship var entry: WordEntry?

    var source: WordImportSource {
        get { WordImportSource(rawValue: sourceRawValue) ?? .manual }
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
        payloadSchemaVersion: Int? = nil,
        metadata: [String: String] = [:],
        createdAt: Date = .now
    ) {
        self.id = id
        self.entry = entry
        self.sourceRawValue = source.rawValue
        self.sourceText = sourceText
        self.selectedCandidate = selectedCandidate
        self.recognizedText = recognizedText
        self.entryID = entry?.id
        self.imageData = imageData
        self.submissionPayloadID = submissionPayloadID
        self.candidatePayloadID = candidatePayloadID
        self.payloadSchemaVersion = payloadSchemaVersion
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
        var added = 0
        var duplicated = 0

        for outcome in outcomes {
            switch outcome {
            case .added: added += 1
            case .duplicate: duplicated += 1
            }
        }

        self.addedCount = added
        self.duplicateCount = duplicated
    }
}
