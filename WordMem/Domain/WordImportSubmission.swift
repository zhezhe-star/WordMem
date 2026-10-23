import Foundation

enum WordImportSource: String, Codable, CaseIterable, Hashable, Sendable {
    case manual
    case image
    case text
    case defaultApp = "default_app"
    case shareExtension = "share_extension"
    case translationProvider = "translation_provider"

    var displayName: String {
        switch self {
        case .manual: "手动添加"
        case .image: "图片识别"
        case .text: "文本选择"
        case .defaultApp: "应用导入"
        case .shareExtension: "分享导入"
        case .translationProvider: "翻译导入"
        }
    }

    var systemImage: String {
        switch self {
        case .manual: "square.and.pencil"
        case .image: "photo.on.rectangle"
        case .text: "text.quote"
        case .defaultApp: "app.badge.fill"
        case .shareExtension: "square.and.arrow.up"
        case .translationProvider: "character.book.closed"
        }
    }
}

/// The one request format written by import surfaces and consumed by WordMem.
struct WordImportSubmission: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    var payloadID: UUID
    var schemaVersion: Int
    var source: WordImportSource
    var sourceText: String
    var recognizedText: String?
    var imageData: Data?
    var candidates: [WordImportCandidatePayload]
    var metadata: [String: String]
    var createdAt: Date

    var id: UUID { payloadID }

    init(
        payloadID: UUID = UUID(),
        schemaVersion: Int = WordImportSubmission.currentSchemaVersion,
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
        schemaVersion =
            try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? Self.currentSchemaVersion
        source = try container.decode(WordImportSource.self, forKey: .source)
        sourceText = try container.decodeIfPresent(String.self, forKey: .sourceText) ?? ""
        recognizedText = try container.decodeIfPresent(String.self, forKey: .recognizedText)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        candidates =
            try container.decodeIfPresent(
                [WordImportCandidatePayload].self,
                forKey: .candidates
            ) ?? []
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
    }
}

/// A selected word/phrase plus the user-edited fields captured before submission.
struct WordImportCandidatePayload: Codable, Equatable, Hashable, Identifiable, Sendable {
    var payloadID: UUID
    var text: String
    var normalizedKey: String
    var userTranslation: String?
    var userPhonetic: String?
    var userExample: String?
    var userNote: String?
    var metadata: [String: String]

    var id: UUID { payloadID }

    init(
        payloadID: UUID = UUID(),
        text: String,
        normalizedKey: String,
        userTranslation: String? = nil,
        userPhonetic: String? = nil,
        userExample: String? = nil,
        userNote: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.payloadID = payloadID
        self.text = text
        self.normalizedKey = normalizedKey
        self.userTranslation = userTranslation
        self.userPhonetic = userPhonetic
        self.userExample = userExample
        self.userNote = userNote
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case payloadID = "payload_id"
        case text
        case normalizedKey = "normalized_key"
        case userTranslation = "user_translation"
        case userPhonetic = "user_phonetic"
        case userExample = "user_example"
        case userNote = "user_note"
        case metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        payloadID = try container.decodeIfPresent(UUID.self, forKey: .payloadID) ?? UUID()
        text = try container.decode(String.self, forKey: .text)
        normalizedKey = try container.decodeIfPresent(String.self, forKey: .normalizedKey) ?? text
        userTranslation = try container.decodeIfPresent(String.self, forKey: .userTranslation)
        userPhonetic = try container.decodeIfPresent(String.self, forKey: .userPhonetic)
        userExample = try container.decodeIfPresent(String.self, forKey: .userExample)
        userNote = try container.decodeIfPresent(String.self, forKey: .userNote)
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

/// Builds a translation-provider payload while preserving the card order shown
/// to the user. Selection is explicit: the phrase is included only when its own
/// chip was selected.
struct TranslationProviderSubmissionBuilder {
    let sourceText: String
    let phraseTranslation: String
    let selectedChips: Set<String>
    let meanings: [String: String]
    let advisedChips: [ImportCandidateChip]

    init(
        sourceText: String,
        phraseTranslation: String,
        selectedChips: Set<String>,
        meanings: [String: String],
        advisedChips: [ImportCandidateChip] = []
    ) {
        self.sourceText = sourceText
        self.phraseTranslation = phraseTranslation
        self.selectedChips = selectedChips
        self.meanings = meanings
        self.advisedChips = advisedChips
    }

    var sourceChips: [String] {
        let advised = advisedChips.map(\.text)
        return advised.isEmpty ? TranslationWordTokenizer.pickerChips(from: sourceText) : advised
    }

    var selectedCandidates: [WordImportCandidatePayload] {
        sourceChips
            .enumerated()
            .compactMap { offset, chipText in
                guard selectedChips.contains(chipText) else { return nil }
                let phrase = TranslationWordTokenizer.normalizedPhrase(from: sourceText)
                let meaning =
                    meanings[chipText]
                    ?? (chipText == phrase ? phraseTranslation : nil)
                    ?? ""
                let trimmedMeaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)

                if let advisedChip = advisedChips.first(where: { $0.id == chipText }) {
                    var payload = ImportCandidatePipeline.payload(from: advisedChip)
                    payload.userTranslation = trimmedMeaning.isEmpty ? nil : trimmedMeaning
                    return payload
                }

                return WordImportCandidatePayload(
                    text: chipText,
                    normalizedKey: chipText.lowercased(),
                    userTranslation: trimmedMeaning.isEmpty ? nil : trimmedMeaning,
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
    private enum Phase: Equatable {
        case idle
        case saving
        case succeeded
    }

    private var phase = Phase.idle

    var isSaving: Bool { phase == .saving }
    var hasSucceeded: Bool { phase == .succeeded }

    mutating func beginSaving() -> Bool {
        guard phase == .idle else { return false }
        phase = .saving
        return true
    }

    mutating func markSucceeded() {
        guard phase == .saving else { return }
        phase = .succeeded
    }

    mutating func endSaving() {
        guard phase == .saving else { return }
        phase = .idle
    }
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

        // The terminal latch must be installed before persistence state is
        // cleared, so an interleaved caller can never observe a retryable save.
        if didSave {
            state.markSucceeded()
        }
        state.endSaving()

        guard didSave else {
            return .completed(storage.persistenceMessage ?? "保存导入记录失败，请重试。")
        }

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
        onSaved: () -> Void
    ) -> String? {
        save(submission, storage: storage, onSaved: onSaved)
    }

    private static func save(
        _ submission: WordImportSubmission,
        storage: any WordImportSubmissionStoring,
        onSaved: () -> Void
    ) -> String? {
        guard storage.appendSubmission(submission) else {
            return storage.persistenceMessage ?? "保存导入记录失败，请重试。"
        }
        onSaved()
        return nil
    }
}

enum WordImportSubmissionQueue {
    static let pendingKey = "pending_word_import_submissions.v1"
    static let legacyPendingBackupKey =
        "pending_word_import_submissions.v1.backup.beforeFileQueue"
    static let appGroupIdentifier = "group.com.zhezhe.wordmem"
    private static let rootDirectoryName = "word-import-submissions"

    static func defaultBaseDirectory() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(rootDirectoryName, isDirectory: true)
    }

    static func directory(
        _ directory: WordImportQueueDirectory,
        baseDirectory base: URL? = nil
    ) throws -> URL {
        let root =
            try base ?? defaultBaseDirectory()
            ?? { throw WordImportQueueError.appGroupContainerUnavailable }()
        let url = root.appendingPathComponent(directory.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func append(
        _ submission: WordImportSubmission,
        baseDirectory base: URL? = nil,
        legacyDefaults: UserDefaults? = nil,
        migrateLegacy: ((UserDefaults?, URL?) throws -> Void)? = nil
    ) throws {
        // Migrate first: a failure here must never leave a newly appended
        // payload behind while reporting the append as failed.
        let migrator = migrateLegacy ?? migrateLegacySubmissions(from:baseDirectory:)
        try migrator(legacyDefaults, base)
        let url = try directory(.pending, baseDirectory: base)
            .appendingPathComponent(filename(for: submission.payloadID))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(submission).write(
            to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    static func snapshot(
        baseDirectory base: URL? = nil,
        legacyDefaults: UserDefaults? = nil
    ) throws -> WordImportQueueSnapshot {
        try migrateLegacySubmissions(from: legacyDefaults, baseDirectory: base)
        let pendingDirectory = try directory(.pending, baseDirectory: base)
        let files = try FileManager.default.contentsOfDirectory(
            at: pendingDirectory,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        .filter { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true && url.pathExtension == "json"
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var pending: [WordImportSubmission] = []
        for file in files {
            let data: Data
            do {
                data = try Data(contentsOf: file)
            } catch {
                try quarantineFile(at: file, directory: .malformed, baseDirectory: base)
                continue
            }

            if try quarantineIfFutureSchema(
                data,
                sourceURL: file,
                baseDirectory: base
            ) != nil {
                continue
            }

            do {
                pending.append(try decodeSubmission(from: data))
            } catch {
                try quarantineFile(at: file, directory: .malformed, baseDirectory: base)
            }
        }

        let malformedCount = try existingFileCount(
            in: directory(.malformed, baseDirectory: base)
        )
        let futureSchemaCount = try existingFileCount(
            in: directory(.futureSchema, baseDirectory: base)
        )
        return WordImportQueueSnapshot(
            pending: pending,
            malformedCount: malformedCount,
            futureSchemaCount: futureSchemaCount
        )
    }

    static func load(
        baseDirectory base: URL? = nil,
        legacyDefaults: UserDefaults? = nil
    ) -> [WordImportSubmission] {
        (try? snapshot(baseDirectory: base, legacyDefaults: legacyDefaults).pending) ?? []
    }

    static func remove(
        _ payloadIDs: Set<UUID>,
        baseDirectory base: URL? = nil,
        legacyDefaults: UserDefaults? = nil
    ) throws {
        guard !payloadIDs.isEmpty else { return }
        let pendingDirectory = try directory(.pending, baseDirectory: base)
        for payloadID in payloadIDs {
            try? FileManager.default.removeItem(
                at: pendingDirectory.appendingPathComponent(filename(for: payloadID))
            )
        }
        legacyDefaults?.removeObject(forKey: pendingKey)
    }

    private static func existingFileCount(in url: URL) throws -> Int {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        .filter { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true && url.pathExtension == "json"
        }
        .count
    }

    static func attentionMessage(for snapshot: WordImportQueueSnapshot) -> String? {
        switch (snapshot.malformedCount, snapshot.futureSchemaCount) {
        case (0, 0):
            nil
        case (0, let future):
            "发现 \(future) 条较新格式的导入记录，已隔离保存，请更新 WordMem。"
        case (let malformed, 0):
            "发现 \(malformed) 条无法读取的导入记录，已隔离保存，不会影响其他导入。"
        case (let malformed, let future):
            "发现 \(future) 条较新格式的导入记录和 \(malformed) 条无法读取的导入记录，已分别隔离保存；更新 WordMem 后可恢复较新记录。"
        }
    }

    @available(*, deprecated, message: "Use the durable file queue API.")
    static func append(_ submission: WordImportSubmission, to defaults: UserDefaults) {
        try? append(submission, baseDirectory: defaultBaseDirectory(), legacyDefaults: defaults)
    }

    @available(*, deprecated, message: "Use snapshot(baseDirectory:legacyDefaults:).")
    static func load(from defaults: UserDefaults) -> [WordImportSubmission] {
        load(baseDirectory: defaultBaseDirectory(), legacyDefaults: defaults)
    }

    @available(*, deprecated, message: "Use remove(baseDirectory:legacyDefaults:).")
    static func remove(_ payloadIDs: Set<UUID>, from defaults: UserDefaults) {
        try? remove(payloadIDs, baseDirectory: defaultBaseDirectory(), legacyDefaults: defaults)
    }

    private static func filename(for payloadID: UUID) -> String {
        "\(payloadID.uuidString).json"
    }

    private static func decodeSubmission(from data: Data) throws -> WordImportSubmission {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WordImportSubmission.self, from: data)
    }

    private static func schemaVersion(in data: Data) -> Int? {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return object?["schema_version"] as? Int
    }

    private static func quarantineIfFutureSchema(
        _ data: Data,
        sourceURL: URL,
        baseDirectory: URL?
    ) throws -> URL? {
        guard let version = schemaVersion(in: data),
            version > WordImportSubmission.currentSchemaVersion
        else { return nil }
        return try quarantineFile(
            at: sourceURL,
            directory: .futureSchema,
            baseDirectory: baseDirectory
        )
    }

    private static func uniqueDestination(filename: String, in directory: URL) -> URL {
        var destination = directory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(UUID().uuidString)-\(filename)")
        }
        return destination
    }

    @discardableResult
    private static func quarantineFile(
        at sourceURL: URL,
        directory targetDirectory: WordImportQueueDirectory,
        baseDirectory: URL?
    ) throws -> URL {
        let destinationDirectory = try directory(targetDirectory, baseDirectory: baseDirectory)
        let destination = uniqueDestination(
            filename: sourceURL.lastPathComponent,
            in: destinationDirectory
        )
        try FileManager.default.moveItem(at: sourceURL, to: destination)
        return destination
    }

    private static func quarantineData(
        _ data: Data,
        sourceFilename: String,
        directory targetDirectory: WordImportQueueDirectory,
        baseDirectory: URL?
    ) throws {
        let destinationDirectory = try directory(targetDirectory, baseDirectory: baseDirectory)
        let destination = uniqueDestination(filename: sourceFilename, in: destinationDirectory)
        try data.write(
            to: destination,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    private static func migrateLegacySubmissions(
        from defaults: UserDefaults?,
        baseDirectory: URL?
    ) throws {
        guard let defaults, let data = defaults.data(forKey: pendingKey) else { return }
        let objects = ((try? JSONSerialization.jsonObject(with: data)) as? [Any]) ?? []
        for object in objects {
            guard let payloadData = try? JSONSerialization.data(withJSONObject: object) else {
                try quarantineObject(object, directory: .malformed, baseDirectory: baseDirectory)
                continue
            }

            let payloadID = payloadID(in: payloadData)
            if let version = schemaVersion(in: payloadData),
                version > WordImportSubmission.currentSchemaVersion
            {
                try quarantineData(
                    payloadData,
                    sourceFilename: filename(for: payloadID),
                    directory: .futureSchema,
                    baseDirectory: baseDirectory
                )
            } else if let submission = try? decodeSubmission(from: payloadData) {
                let url = try directory(.pending, baseDirectory: baseDirectory)
                    .appendingPathComponent(filename(for: submission.payloadID))
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(submission).write(
                    to: url,
                    options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                )
            } else {
                try quarantineData(
                    payloadData,
                    sourceFilename: filename(for: payloadID),
                    directory: .malformed,
                    baseDirectory: baseDirectory
                )
            }
        }

        defaults.set(data, forKey: legacyPendingBackupKey)
        defaults.removeObject(forKey: pendingKey)
    }

    private static func payloadID(in data: Data) -> UUID {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let rawID = object["payload_id"] as? String,
            let id = UUID(uuidString: rawID)
        else { return UUID() }
        return id
    }

    private static func quarantineObject(
        _ object: Any,
        directory targetDirectory: WordImportQueueDirectory,
        baseDirectory: URL?
    ) throws {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        try quarantineData(
            data,
            sourceFilename: "\(UUID().uuidString).json",
            directory: targetDirectory,
            baseDirectory: baseDirectory
        )
    }
}
