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

/// The one request format written by extension targets and consumed by WordMem.
struct WordImportSubmission: Codable, Equatable, Identifiable, Sendable {
  static let currentSchemaVersion = 1

  var payloadID: UUID
  var schemaVersion: Int
  var source: WordImportSource
  var sourceText: String
  var recognizedText: String?
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
    candidates: [WordImportCandidatePayload],
    metadata: [String: String] = [:],
    createdAt: Date = .now
  ) {
    self.payloadID = payloadID
    self.schemaVersion = schemaVersion
    self.source = source
    self.sourceText = sourceText
    self.recognizedText = recognizedText
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
    case candidates
    case metadata
    case createdAt = "created_at"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    payloadID = try container.decodeIfPresent(UUID.self, forKey: .payloadID) ?? UUID()
    schemaVersion =
      try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
    source = try container.decode(WordImportSource.self, forKey: .source)
    sourceText = try container.decodeIfPresent(String.self, forKey: .sourceText) ?? ""
    recognizedText = try container.decodeIfPresent(String.self, forKey: .recognizedText)
    candidates =
      try container.decodeIfPresent([WordImportCandidatePayload].self, forKey: .candidates) ?? []
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

enum WordImportSubmissionQueue {
  static let pendingKey = "pending_word_import_submissions.v1"

  static func append(_ submission: WordImportSubmission, to defaults: UserDefaults) {
    var submissions = load(from: defaults)
    submissions.removeAll { $0.payloadID == submission.payloadID }
    submissions.append(submission)
    save(submissions, to: defaults)
  }

  static func load(from defaults: UserDefaults) -> [WordImportSubmission] {
    guard let data = defaults.data(forKey: pendingKey) else { return [] }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode([WordImportSubmission].self, from: data)) ?? []
  }

  static func remove(_ payloadIDs: Set<UUID>, from defaults: UserDefaults) {
    guard !payloadIDs.isEmpty else { return }
    save(load(from: defaults).filter { !payloadIDs.contains($0.payloadID) }, to: defaults)
  }

  private static func save(_ submissions: [WordImportSubmission], to defaults: UserDefaults) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    if let data = try? encoder.encode(submissions) {
      defaults.set(data, forKey: pendingKey)
    }
  }
}
