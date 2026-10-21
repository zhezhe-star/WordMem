import Foundation
import SwiftData

enum WordImportSource: String, Codable, CaseIterable, Hashable, Sendable {
    case manual
    case image
    case text
    case defaultApp = "default_app"

    var displayName: String {
        switch self {
        case .manual: "手动添加"
        case .image: "图片识别"
        case .text: "文本选择"
        case .defaultApp: "应用导入"
        }
    }

    var systemImage: String {
        switch self {
        case .manual: "square.and.pencil"
        case .image: "photo.on.rectangle"
        case .text: "text.quote"
        case .defaultApp: "app.badge.fill"
        }
    }
}

@Model
final class WordImportContext {
    var id: UUID
    var sourceRawValue: String
    var sourceText: String?
    var selectedCandidate: String?
    var recognizedText: String?
    @Attribute(.externalStorage) var imageData: Data?
    var entryID: UUID?
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
        self.metadataData = (try? JSONEncoder().encode(metadata)) ?? Data()
        self.createdAt = createdAt
    }
}

struct WordImportCandidate: Identifiable, Hashable {
    var text: String
    var normalizedKey: String

    var id: String { normalizedKey }
}

struct WordImportSelection: Equatable {
    private(set) var deselectedKeys: Set<String> = []

    mutating func toggle(_ key: String) {
        if deselectedKeys.contains(key) {
            deselectedKeys.remove(key)
        } else {
            deselectedKeys.insert(key)
        }
    }

    func isSelected(_ key: String) -> Bool {
        !deselectedKeys.contains(key)
    }

    func selectedWords(in candidates: [WordImportCandidate]) -> [String] {
        candidates.filter { isSelected($0.normalizedKey) }.map(\.text)
    }
}

enum EnglishWordCandidateSplitter {
    private static let expression = try! NSRegularExpression(
        pattern: #"[A-Za-z]+(?:['’][A-Za-z]+|-[A-Za-z]+)*"#,
        options: []
    )

    static func candidates(from sourceText: String) -> [WordImportCandidate] {
        var candidates: [WordImportCandidate] = []
        var seenKeys = Set<String>()

        let range = NSRange(sourceText.startIndex..., in: sourceText)
        for match in expression.matches(in: sourceText, range: range) {
            guard let matchRange = Range(match.range, in: sourceText) else { continue }
            let text = String(sourceText[matchRange])
            // Contraction apostrophes are spelling details; candidate identity uses the bare word.
            let key = WordInputNormalizer.normalizedKey(from: text)
                .replacingOccurrences(of: "'", with: "")
            guard !key.isEmpty, seenKeys.insert(key).inserted else { continue }
            candidates.append(
                WordImportCandidate(text: text, normalizedKey: key)
            )
        }

        return candidates
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
