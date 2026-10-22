import Foundation
import SwiftData
import XCTest

@testable import WordMem

@MainActor
final class WordImportSubmissionTests: XCTestCase {
  private func makeSubmission(
    source: WordImportSource = .shareExtension,
    candidates: [WordImportCandidatePayload] = [
      WordImportCandidatePayload(
        text: "running",
        normalizedKey: "running",
        userTranslation: "奔跑中",
        userPhonetic: "/custom/"
      )
    ]
  ) -> WordImportSubmission {
    WordImportSubmission(
      payloadID: UUID(uuidString: "D6AA4014-7601-4F18-856C-48D6391C90BB")!,
      source: source,
      sourceText: "The running idea.",
      recognizedText: "The running idea.",
      candidates: candidates,
      metadata: ["channel": "share"],
      createdAt: ISO8601DateFormatter().date(from: "2026-02-03T04:05:06Z")!
    )
  }

  private func makeContainer() throws -> ModelContainer {
    try ModelContainer(
      for: WordEntry.self,
      WordImportContext.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
  }

  func testSourceKeepsLegacyDefaultAppAndAddsExtensionIdentities() {
    XCTAssertEqual(WordImportSource.defaultApp.rawValue, "default_app")
    XCTAssertEqual(WordImportSource.shareExtension.rawValue, "share_extension")
    XCTAssertEqual(WordImportSource.translationProvider.rawValue, "translation_provider")
    XCTAssertEqual(WordImportSource.shareExtension.displayName, "分享导入")
    XCTAssertEqual(WordImportSource.translationProvider.displayName, "翻译导入")
  }

  func testSubmissionRoundTripAndCompatibleJSONFieldNames() throws {
    let submission = makeSubmission()
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(submission)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertNotNil(object["payload_id"] as Any)
    XCTAssertEqual(object["schema_version"] as? Int, 1)
    XCTAssertEqual(object["source"] as? String, "share_extension")
    XCTAssertEqual(object["source_text"] as? String, "The running idea.")
    XCTAssertNotNil(object["candidates"] as Any)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(WordImportSubmission.self, from: data)
    XCTAssertEqual(decoded, submission)

    let legacyJSON = """
      {
        "payload_id": "D6AA4014-7601-4F18-856C-48D6391C90BB",
        "schema_version": 1,
        "source": "translation_provider",
        "source_text": "A beautiful day.",
        "recognized_text": null,
        "metadata": {"channel": "translation"},
        "created_at": "2026-02-03T04:05:06Z",
        "candidates": [
          {
            "payload_id": "9E5F2B94-4753-459B-951C-6B93D93D6A4D",
            "text": "beautiful",
            "normalized_key": "beautiful",
            "user_translation": "我自己的解释",
            "user_phonetic": "/mine/",
            "user_example": "A beautiful test.",
            "user_note": "记住它",
            "metadata": {"position": "1"}
          }
        ]
      }
      """
    let legacy = try decoder.decode(
      WordImportSubmission.self,
      from: Data(legacyJSON.utf8)
    )
    XCTAssertEqual(legacy.source, .translationProvider)
    XCTAssertEqual(legacy.candidates.first?.userTranslation, "我自己的解释")
    XCTAssertEqual(legacy.candidates.first?.metadata["position"], "1")
  }

  func testAppGroupStorageAppendsLoadsAndRemovesSubmissionBatches() throws {
    let suite = "WordImportSubmissionStorage.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let storage = defaults
    let first = makeSubmission()
    var second = makeSubmission()
    second.payloadID = UUID()
    second.source = .translationProvider

    WordImportSubmissionQueue.append(first, to: storage)
    WordImportSubmissionQueue.append(second, to: storage)

    XCTAssertEqual(
      WordImportSubmissionQueue.load(from: storage).map(\.payloadID),
      [first.payloadID, second.payloadID])

    WordImportSubmissionQueue.remove([first.payloadID], from: storage)
    XCTAssertEqual(
      WordImportSubmissionQueue.load(from: storage).map(\.payloadID), [second.payloadID])
  }

  func testStructuredRepositoryImportCreatesPerCandidateHistoryAndPreservesUserData() async throws {
    let container = try makeContainer()
    let modelContext = ModelContext(container)
    let repository = WordbookRepository(modelContext: modelContext)
    let dictionary = BundledDictionaryLookupService(
      catalog: DevelopmentSeedDictionaryCatalog.entries
    )
    let candidate = WordImportCandidatePayload(
      text: "running",
      normalizedKey: "running",
      userTranslation: "奔跑中",
      userPhonetic: "/custom/",
      userExample: "The running test.",
      userNote: "重点词"
    )
    let submission = makeSubmission(
      source: .translationProvider,
      candidates: [candidate]
    )

    let outcomes = try await repository.importSubmission(submission, using: dictionary)

    XCTAssertEqual(outcomes.count, 1)
    let entry = try XCTUnwrap(outcomes.first?.entry)
    XCTAssertEqual(entry.normalizedKey, "run")
    XCTAssertEqual(entry.translation, "跑；奔跑")
    XCTAssertEqual(entry.userTranslation, "奔跑中")
    XCTAssertEqual(entry.phonetic, "/custom/")
    XCTAssertEqual(entry.legacyExample, "The running test.")

    let contexts = try modelContext.fetch(FetchDescriptor<WordImportContext>())
    XCTAssertEqual(contexts.count, 1)
    let context = try XCTUnwrap(contexts.first)
    XCTAssertEqual(context.source, .translationProvider)
    XCTAssertEqual(context.sourceText, submission.sourceText)
    XCTAssertEqual(context.selectedCandidate, "running")
    XCTAssertEqual(context.entryID, entry.id)
    XCTAssertEqual(context.metadata["payloadID"], submission.payloadID.uuidString)
    XCTAssertEqual(context.metadata["payloadSchemaVersion"], "1")
    XCTAssertEqual(context.metadata["userNote"], "重点词")
  }

  func testDuplicateSubmissionPreservesHistoricalContextsInOneTransaction() async throws {
    let container = try makeContainer()
    let modelContext = ModelContext(container)
    let repository = WordbookRepository(modelContext: modelContext)
    let dictionary = BundledDictionaryLookupService(
      catalog: DevelopmentSeedDictionaryCatalog.entries
    )
    let submission = makeSubmission()

    _ = try await repository.importSubmission(submission, using: dictionary)
    _ = try await repository.importSubmission(submission, using: dictionary)

    XCTAssertEqual(try modelContext.fetch(FetchDescriptor<WordEntry>()).count, 1)
    XCTAssertEqual(try modelContext.fetch(FetchDescriptor<WordImportContext>()).count, 2)
  }

  func testPendingSubmissionMigrationImportsOnceAndPreservesOnlyFailures() async throws {
    let suite = "WordImportSubmissionMigration.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let storage = defaults
    let valid = makeSubmission(
      source: .shareExtension,
      candidates: [
        WordImportCandidatePayload(
          text: "run",
          normalizedKey: "run",
          userTranslation: "我的跑"
        )
      ]
    )
    WordImportSubmissionQueue.append(valid, to: storage)

    let container = try makeContainer()
    let modelContext = ModelContext(container)
    let dictionary = BundledDictionaryLookupService(
      catalog: DevelopmentSeedDictionaryCatalog.entries
    )

    try await WordImportSubmissionMigrator.processPendingSubmissions(
      defaults: defaults,
      into: modelContext,
      dictionaryService: dictionary
    )
    try await WordImportSubmissionMigrator.processPendingSubmissions(
      defaults: defaults,
      into: modelContext,
      dictionaryService: dictionary
    )

    let entries = try modelContext.fetch(FetchDescriptor<WordEntry>())
    let contexts = try modelContext.fetch(FetchDescriptor<WordImportContext>())
    XCTAssertEqual(entries.count, 1)
    XCTAssertEqual(contexts.count, 1)
    XCTAssertEqual(entries.first?.userTranslation, "我的跑")
    XCTAssertEqual(entries.first?.translation, "跑；奔跑")
    XCTAssertEqual(contexts.first?.source, .shareExtension)
    XCTAssertEqual(contexts.first?.metadata["payloadID"], valid.payloadID.uuidString)
    XCTAssertTrue(WordImportSubmissionQueue.load(from: storage).isEmpty)
  }

  func testMigrationProcessesSuccessfulSubmissionBeforeLeavingFailedBatch() async throws {
    let suite = "WordImportPartialMigration.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let storage = defaults
    let valid = makeSubmission(source: .translationProvider)
    var invalid = makeSubmission(
      source: .shareExtension,
      candidates: []
    )
    invalid.payloadID = UUID()
    invalid.createdAt = valid.createdAt.addingTimeInterval(1)
    WordImportSubmissionQueue.append(valid, to: storage)
    WordImportSubmissionQueue.append(invalid, to: storage)

    let container = try makeContainer()
    let modelContext = ModelContext(container)
    let dictionary = BundledDictionaryLookupService(
      catalog: DevelopmentSeedDictionaryCatalog.entries
    )

    do {
      _ = try await WordImportSubmissionMigrator.processPendingSubmissions(
        defaults: defaults,
        into: modelContext,
        dictionaryService: dictionary
      )
      XCTFail("Expected empty submission to fail")
    } catch let error as WordImportError {
      XCTAssertEqual(error, .emptySelection)
    }

    XCTAssertEqual(try modelContext.fetch(FetchDescriptor<WordImportContext>()).count, 1)
    XCTAssertEqual(
      WordImportSubmissionQueue.load(from: storage).map(\.payloadID), [invalid.payloadID])
  }

  func testLegacySavedWordsStillMigrateToSwiftData() async throws {
    let suite = "WordLegacyCompatibility.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let legacy = WordData(word: "ran", translation: "旧释义")
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    defaults.set(try encoder.encode([legacy]), forKey: "saved_words")

    let container = try makeContainer()
    let modelContext = ModelContext(container)
    try await LegacyWordbookMigrator.migrateIfNeeded(defaults: defaults, into: modelContext)

    let entries = try modelContext.fetch(FetchDescriptor<WordEntry>())
    XCTAssertEqual(entries.count, 1)
    XCTAssertEqual(entries.first?.userTranslation, "旧释义")
    XCTAssertNil(defaults.data(forKey: "saved_words"))
  }
}
