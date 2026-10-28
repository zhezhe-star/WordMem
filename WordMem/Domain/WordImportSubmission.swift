import Foundation

enum WordImportSource: String, Codable, CaseIterable, Hashable, Sendable {
    case image
    case text
    case defaultApp = "default_app"
    case shareExtension = "share_extension"
    case translationProvider = "translation_provider"

    var displayName: String {
        switch self {
        case .image: "图片识别"
        case .text: "文本选择"
        case .defaultApp: "应用导入"
        case .shareExtension: "分享导入"
        case .translationProvider: "翻译导入"
        }
    }

    var systemImage: String {
        switch self {
        case .image: "photo.on.rectangle"
        case .text: "text.quote"
        case .defaultApp: "app.badge.fill"
        case .shareExtension: "square.and.arrow.up"
        case .translationProvider: "character.book.closed"
        }
    }
}

struct WordImportSubmission: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 4

    var payloadID: UUID
    var schemaVersion: Int
    var localeIdentifier: String
    var source: WordImportSource
    var sourceText: String
    var recognizedText: String?
    var imageData: Data?
    var candidates: [WordImportCandidatePayload]
    var metadata: [String: String]
    var createdAt: Date

    var id: UUID { payloadID }
    var locale: Locale { Locale(identifier: localeIdentifier) }

    init(
        payloadID: UUID = UUID(),
        schemaVersion: Int = WordImportSubmission.currentSchemaVersion,
        localeIdentifier: String = WordIdentity.defaultLocaleIdentifier,
        source: WordImportSource,
        sourceText: String,
        recognizedText: String? = nil,
        imageData: Data? = nil,
        candidates: [WordImportCandidatePayload],
        metadata: [String: String] = [:],
        createdAt: Date = .now
    ) {
        self.payloadID = payloadID
        self.schemaVersion = schemaVersion
        self.localeIdentifier = localeIdentifier
        self.source = source
        self.sourceText = sourceText
        self.recognizedText = recognizedText
        self.imageData = imageData
        self.candidates = candidates
        self.metadata = metadata
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case payloadID = "payload_id"
        case schemaVersion = "schema_version"
        case localeIdentifier = "locale_identifier"
        case source
        case sourceText = "source_text"
        case recognizedText = "recognized_text"
        case imageData = "image_data"
        case candidates
        case metadata
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        payloadID = try container.decodeIfPresent(UUID.self, forKey: .payloadID) ?? UUID()
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        localeIdentifier = try container.decodeIfPresent(String.self, forKey: .localeIdentifier) ?? WordIdentity.defaultLocaleIdentifier
        source = try container.decode(WordImportSource.self, forKey: .source)
        sourceText = try container.decodeIfPresent(String.self, forKey: .sourceText) ?? ""
        recognizedText = try container.decodeIfPresent(String.self, forKey: .recognizedText)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        candidates = try container.decodeIfPresent([WordImportCandidatePayload].self, forKey: .candidates) ?? []
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
    }

    func mergedMetadata(for candidate: WordImportCandidatePayload) -> [String: String] {
        var merged = metadata
        merged.merge(candidate.metadata) { _, candidateValue in candidateValue }
        merged["submissionPayloadID"] = payloadID.uuidString
        merged["candidatePayloadID"] = candidate.payloadID.uuidString
        merged["schemaVersion"] = String(schemaVersion)
        return merged
    }
}

struct WordImportCandidatePayload: Codable, Equatable, Hashable, Identifiable, Sendable {
    var payloadID: UUID
    var text: String
    var normalizedKey: String
    var translation: String?
    var example: String?
    var note: String?
    var metadata: [String: String]

    var id: UUID { payloadID }

    init(
        payloadID: UUID = UUID(),
        text: String,
        normalizedKey: String,
        translation: String? = nil,
        example: String? = nil,
        note: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.payloadID = payloadID
        self.text = text
        self.normalizedKey = normalizedKey
        self.translation = translation
        self.example = example
        self.note = note
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case payloadID = "payload_id"
        case text
        case normalizedKey = "normalized_key"
        case translation = "translation"
        case example = "example"
        case note = "note"
        case metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        payloadID = try container.decodeIfPresent(UUID.self, forKey: .payloadID) ?? UUID()
        text = try container.decode(String.self, forKey: .text)
        normalizedKey = try container.decodeIfPresent(String.self, forKey: .normalizedKey) ?? text
        translation = try container.decodeIfPresent(String.self, forKey: .translation)
        example = try container.decodeIfPresent(String.self, forKey: .example)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }
}

struct WordImportQueueSnapshot: Equatable, Sendable {
    var pending: [WordImportSubmission]
    var malformedCount: Int
    var futureSchemaCount: Int

    var hasAttention: Bool { malformedCount > 0 || futureSchemaCount > 0 }
}

enum WordImportQueueDirectory: String, Sendable {
    case pending
    case malformed
    case futureSchema = "future-schema"
}

enum WordImportQueueError: Error, Equatable {
    case appGroupContainerUnavailable
}

struct TranslationProviderSubmissionBuilder {
    let sourceText: String
    let phraseTranslation: String
    let selectedChips: Set<String>
    let meanings: [String: String]
    let advisedChips: [ImportCandidateChip]

    var sourceChips: [String] {
        let advised = advisedChips.map(\.text)
        return advised.isEmpty ? TranslationWordTokenizer.pickerChips(from: sourceText) : advised
    }

    var selectedCandidates: [WordImportCandidatePayload] {
        sourceChips.enumerated().compactMap { offset, chipText in
            guard selectedChips.contains(chipText) else { return nil }
            let phrase = TranslationWordTokenizer.normalizedPhrase(from: sourceText)
            let meaning = meanings[chipText] ?? (chipText == phrase ? phraseTranslation : nil) ?? ""
            let trimmedMeaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)

            if let advisedChip = advisedChips.first(where: { $0.id == chipText }) {
                var payload = ImportCandidatePipeline.payload(from: advisedChip)
                payload.translation = trimmedMeaning.isEmpty ? nil : trimmedMeaning
                return payload
            }

            return WordImportCandidatePayload(
                text: chipText,
                normalizedKey: chipText.lowercased(),
                translation: trimmedMeaning.isEmpty ? nil : trimmedMeaning,
                metadata: ["sourceOrder": String(offset)]
            )
        }
    }

    func makeSubmission() -> WordImportSubmission {
        WordImportSubmission(
            source: .translationProvider,
            sourceText: TranslationWordTokenizer.normalizedPhrase(from: sourceText),
            recognizedText: sourceText,
            candidates: selectedCandidates,
            metadata: ["channel": "translation_provider"]
        )
    }
}

struct TranslationProviderSaveState: Equatable {
    private enum Phase: Equatable { case idle, saving, succeeded }
    private var phase = Phase.idle
    var isSaving: Bool { phase == .saving }
    var hasSucceeded: Bool { phase == .succeeded }

    mutating func beginSaving() -> Bool {
        guard phase == .idle else { return false }
        phase = .saving
        return true
    }

    mutating func markSucceeded() { phase = phase == .saving ? .succeeded : phase }
    mutating func endSaving() { phase = phase == .saving ? .idle : phase }
}

@MainActor
final class TranslationProviderSaveCoordinator {
    enum Result: Equatable {
        case completed(String?)
        case ignoredWhileSaving
        case ignoredAfterSuccess
    }

    private var state = TranslationProviderSaveState()
    var isSaving: Bool { state.isSaving }

    func save(
        _ submission: WordImportSubmission,
        storage: any WordImportSubmissionStoring,
        onSaved: () -> Void
    ) -> Result {
        guard state.beginSaving() else {
            return state.hasSucceeded ? .ignoredAfterSuccess : .ignoredWhileSaving
        }
        let didSave = storage.appendSubmission(submission)
        if didSave { state.markSucceeded() }
        state.endSaving()
        guard didSave else { return .completed(storage.persistenceMessage ?? "保存导入记录失败，请重试。") }
        onSaved()
        return .completed(nil)
    }
}

protocol WordImportSubmissionStoring: AnyObject {
    @discardableResult
    func appendSubmission(_ submission: WordImportSubmission) -> Bool
    var persistenceMessage: String? { get }
}

@MainActor
enum WordImportExtensionSaveService {
    static func saveShare(
        _ submission: WordImportSubmission,
        storage: any WordImportSubmissionStoring,
        onSaved: @escaping () -> Void
    ) -> String? {
        let coordinator = TranslationProviderSaveCoordinator()
        if case .completed(let error) = coordinator.save(submission, storage: storage, onSaved: onSaved) {
            return error
        }
        return nil
    }
}

enum WordImportSubmissionQueue {
    static func defaultBaseDirectory() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.zhezhe.wordmem")?
            .appendingPathComponent("WordMemImportQueue", isDirectory: true)
    }

    static func append(
        _ submission: WordImportSubmission,
        baseDirectory base: URL? = nil
    ) throws {
        guard let base = base ?? defaultBaseDirectory() else {
            throw WordImportQueueError.appGroupContainerUnavailable
        }
        let pending = try directory(.pending, baseDirectory: base)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(submission)
        try data.write(
            to: pending.appendingPathComponent(filename(for: submission.payloadID)),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    static func snapshot(baseDirectory base: URL? = nil) throws -> WordImportQueueSnapshot {
        let pendingDirectory = try directory(.pending, baseDirectory: base)
        let files = try FileManager.default.contentsOfDirectory(at: pendingDirectory, includingPropertiesForKeys: [.isRegularFileKey])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var pending: [WordImportSubmission] = []
        for file in files {
            do {
                let data = try Data(contentsOf: file)
                if try quarantineIfFutureSchema(data, sourceURL: file, baseDirectory: base) != nil { continue }
                pending.append(try decodeSubmission(from: data))
            } catch {
                try? quarantineFile(at: file, directory: .malformed, baseDirectory: base)
            }
        }
        return WordImportQueueSnapshot(
            pending: pending,
            malformedCount: try existingFileCount(in: directory(.malformed, baseDirectory: base)),
            futureSchemaCount: try existingFileCount(in: directory(.futureSchema, baseDirectory: base))
        )
    }

    static func load(baseDirectory base: URL? = nil) -> [WordImportSubmission] {
        (try? snapshot(baseDirectory: base).pending) ?? []
    }

    static func remove(_ payloadIDs: Set<UUID>, baseDirectory base: URL? = nil) throws {
        guard let pending = try? directory(.pending, baseDirectory: base) else {
            throw WordImportQueueError.appGroupContainerUnavailable
        }
        for payloadID in payloadIDs {
            try? FileManager.default.removeItem(at: pending.appendingPathComponent(filename(for: payloadID)))
        }
    }

    static func attentionMessage(for snapshot: WordImportQueueSnapshot) -> String? {
        switch (snapshot.malformedCount, snapshot.futureSchemaCount) {
        case (0, 0): nil
        case (0, let future): "发现 \(future) 条较新格式的导入记录，已隔离保存，请更新 WordMem。"
        case (let malformed, 0): "发现 \(malformed) 条无法读取的导入记录，已隔离保存，不会影响其他导入。"
        case (let malformed, let future): "发现 \(future) 条较新格式的导入记录和 \(malformed) 条无法读取的导入记录，已分别隔离保存。"
        }
    }

    private static func directory(_ target: WordImportQueueDirectory, baseDirectory base: URL?) throws -> URL {
        guard let base = base ?? defaultBaseDirectory() else {
            throw WordImportQueueError.appGroupContainerUnavailable
        }
        let url = base.appendingPathComponent(target.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func filename(for payloadID: UUID) -> String { "\(payloadID.uuidString).json" }

    private static func decodeSubmission(from data: Data) throws -> WordImportSubmission {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WordImportSubmission.self, from: data)
    }

    private static func schemaVersion(in data: Data) -> Int? {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["schema_version"] as? Int
    }

    private static func quarantineIfFutureSchema(
        _ data: Data, sourceURL: URL, baseDirectory: URL?
    ) throws -> URL? {
        guard let version = schemaVersion(in: data), version > WordImportSubmission.currentSchemaVersion else { return nil }
        return try quarantineFile(at: sourceURL, directory: .futureSchema, baseDirectory: baseDirectory)
    }

    private static func existingFileCount(in url: URL) throws -> Int {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
            .count
    }

    private static func quarantineFile(
        at sourceURL: URL, directory targetDirectory: WordImportQueueDirectory, baseDirectory: URL?
    ) throws -> URL {
        let destinationDirectory = try directory(targetDirectory, baseDirectory: baseDirectory)
        var destination = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            destination = destinationDirectory.appendingPathComponent("\(UUID().uuidString)-\(sourceURL.lastPathComponent)")
        }
        try FileManager.default.moveItem(at: sourceURL, to: destination)
        return destination
    }
}
