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
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "WordImportSubmissionStorage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = makeSubmission()
        var second = makeSubmission()
        second.payloadID = UUID()
        second.source = .translationProvider

        try WordImportSubmissionQueue.append(first, baseDirectory: root)
        try WordImportSubmissionQueue.append(second, baseDirectory: root)

        XCTAssertEqual(
            Set(
                try WordImportSubmissionQueue.snapshot(baseDirectory: root).pending.map(\.payloadID)
            ),
            [first.payloadID, second.payloadID])

        try WordImportSubmissionQueue.remove([first.payloadID], baseDirectory: root)
        XCTAssertEqual(
            Set(
                try WordImportSubmissionQueue.snapshot(baseDirectory: root).pending.map(\.payloadID)
            ),
            [second.payloadID])
    }

    func testStructuredRepositoryImportCreatesPerCandidateHistoryAndPreservesUserData() async throws
    {
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
        XCTAssertEqual(entry.userExample, "The running test.")
        XCTAssertNil(entry.legacyExample)

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
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "WordImportSubmissionMigration-\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
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
        try WordImportSubmissionQueue.append(valid, baseDirectory: root, legacyDefaults: defaults)

        let container = try makeContainer()
        let modelContext = ModelContext(container)
        let dictionary = BundledDictionaryLookupService(
            catalog: DevelopmentSeedDictionaryCatalog.entries
        )

        let firstResult = try await WordImportSubmissionMigrator.processPendingSubmissions(
            baseDirectory: root,
            legacyDefaults: defaults,
            into: modelContext,
            dictionaryService: dictionary
        )
        let secondResult = try await WordImportSubmissionMigrator.processPendingSubmissions(
            baseDirectory: root,
            legacyDefaults: defaults,
            into: modelContext,
            dictionaryService: dictionary
        )

        XCTAssertEqual(firstResult.importedPayloadCount, 1)
        XCTAssertEqual(secondResult.importedPayloadCount, 0)
        let entries = try modelContext.fetch(FetchDescriptor<WordEntry>())
        let contexts = try modelContext.fetch(FetchDescriptor<WordImportContext>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(contexts.count, 1)
        XCTAssertEqual(entries.first?.userTranslation, "我的跑")
        XCTAssertEqual(entries.first?.translation, "跑；奔跑")
        XCTAssertEqual(contexts.first?.source, .shareExtension)
        XCTAssertEqual(contexts.first?.submissionPayloadID, valid.payloadID)
        XCTAssertTrue(
            try WordImportSubmissionQueue.snapshot(baseDirectory: root, legacyDefaults: defaults)
                .pending.isEmpty)
    }

    func testMigrationProcessesSuccessfulSubmissionBeforeLeavingFailedBatch() async throws {
        let suite = "WordImportPartialMigration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "WordImportPartialMigration-\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let valid = makeSubmission(source: .translationProvider)
        var invalid = makeSubmission(
            source: .shareExtension,
            candidates: []
        )
        invalid.payloadID = UUID()
        invalid.createdAt = valid.createdAt.addingTimeInterval(1)
        try WordImportSubmissionQueue.append(valid, baseDirectory: root, legacyDefaults: defaults)
        try WordImportSubmissionQueue.append(invalid, baseDirectory: root, legacyDefaults: defaults)

        let container = try makeContainer()
        let modelContext = ModelContext(container)
        let dictionary = BundledDictionaryLookupService(
            catalog: DevelopmentSeedDictionaryCatalog.entries
        )

        do {
            _ = try await WordImportSubmissionMigrator.processPendingSubmissions(
                baseDirectory: root,
                legacyDefaults: defaults,
                into: modelContext,
                dictionaryService: dictionary
            )
            XCTFail("Expected empty submission to fail")
        } catch let error as WordImportError {
            XCTAssertEqual(error, .emptySelection)
        }

        XCTAssertEqual(try modelContext.fetch(FetchDescriptor<WordImportContext>()).count, 1)
        XCTAssertEqual(
            try WordImportSubmissionQueue.snapshot(baseDirectory: root, legacyDefaults: defaults)
                .pending.map(\.payloadID),
            [invalid.payloadID])
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

private actor QueueErrorCollector {
    private var failure: Error?

    func record(_ error: Error) {
        if failure == nil { failure = error }
    }

    func throwIfFailed() throws {
        if let failure { throw failure }
    }
}

@MainActor
final class WordImportQueueHardeningTests: XCTestCase {
    private struct Fixture {
        let baseDirectory: URL
        let defaults: UserDefaults
        let defaultsSuite: String
        let container: ModelContainer
        let modelContext: ModelContext
        let repository: WordbookRepository
        let dictionary: BundledDictionaryLookupService
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "WordImportQueueHardening-\(UUID().uuidString)", isDirectory: true)
        let suite = "WordImportQueueHardening.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WordEntry.self,
            WordImportContext.self,
            configurations: configuration
        )
        let modelContext = ModelContext(container)
        return Fixture(
            baseDirectory: root,
            defaults: defaults,
            defaultsSuite: suite,
            container: container,
            modelContext: modelContext,
            repository: WordbookRepository(modelContext: modelContext),
            dictionary: BundledDictionaryLookupService(
                catalog: DevelopmentSeedDictionaryCatalog.entries
            )
        )
    }

    private func cleanup(_ fixture: Fixture) {
        try? FileManager.default.removeItem(at: fixture.baseDirectory)
        fixture.defaults.removePersistentDomain(forName: fixture.defaultsSuite)
    }

    private func submission(
        source: WordImportSource = .shareExtension,
        text: String = "run",
        translation: String? = "我的跑"
    ) -> WordImportSubmission {
        WordImportSubmission(
            source: source,
            sourceText: "The running test.",
            recognizedText: source == .image ? "The running test." : nil,
            imageData: source == .image ? Data([1, 2, 3]) : nil,
            candidates: [
                WordImportCandidatePayload(
                    text: text,
                    normalizedKey: text.lowercased(),
                    userTranslation: translation,
                    userExample: source == .manual ? "My current example." : nil
                )
            ],
            metadata: ["channel": source.rawValue]
        )
    }

    func testConcurrentPayloadFileAppendsAndRemovesCannotLoseBatches() async throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture) }
        let submissions = (0..<24).map { index in
            var value = submission()
            value.payloadID = UUID()
            value.sourceText = "Payload \(index)"
            return value
        }

        let baseDirectory = fixture.baseDirectory
        let errors = QueueErrorCollector()
        await withTaskGroup(of: Void.self) { group in
            for value in submissions {
                group.addTask {
                    do {
                        try WordImportSubmissionQueue.append(
                            value,
                            baseDirectory: baseDirectory
                        )
                    } catch {
                        await errors.record(error)
                    }
                }
            }
        }
        try await errors.throwIfFailed()

        let loaded = try WordImportSubmissionQueue.snapshot(
            baseDirectory: fixture.baseDirectory,
            legacyDefaults: fixture.defaults
        )
        XCTAssertEqual(loaded.pending.count, 24)
        XCTAssertEqual(Set(loaded.pending.map(\.payloadID)), Set(submissions.map(\.payloadID)))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: WordImportSubmissionQueue.directory(
                    .pending, baseDirectory: fixture.baseDirectory),
                includingPropertiesForKeys: nil
            ).count,
            24
        )

        let removedIDs = Set(submissions.prefix(12).map(\.payloadID))
        await withTaskGroup(of: Void.self) { group in
            for id in removedIDs {
                group.addTask {
                    do {
                        try WordImportSubmissionQueue.remove(
                            [id],
                            baseDirectory: baseDirectory
                        )
                    } catch {
                        await errors.record(error)
                    }
                }
            }
        }
        try await errors.throwIfFailed()

        let remaining = try WordImportSubmissionQueue.snapshot(
            baseDirectory: fixture.baseDirectory,
            legacyDefaults: fixture.defaults
        )
        XCTAssertEqual(remaining.pending.count, 12)
        XCTAssertEqual(
            Set(remaining.pending.map(\.payloadID)), Set(submissions.dropFirst(12).map(\.payloadID))
        )
    }

    func testMalformedAndFuturePayloadsAreQuarantinedSeparatelyWithoutHidingValidPayload() throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture) }
        let valid = submission()
        var future = submission()
        future.payloadID = UUID()
        future.schemaVersion = WordImportSubmission.currentSchemaVersion + 1
        try WordImportSubmissionQueue.append(valid, baseDirectory: fixture.baseDirectory)
        try WordImportSubmissionQueue.append(future, baseDirectory: fixture.baseDirectory)
        let malformedName = UUID().uuidString + ".json"
        try Data("not-json".utf8).write(
            to: WordImportSubmissionQueue.directory(.pending, baseDirectory: fixture.baseDirectory)
                .appendingPathComponent(malformedName)
        )

        let snapshot = try WordImportSubmissionQueue.snapshot(
            baseDirectory: fixture.baseDirectory,
            legacyDefaults: fixture.defaults
        )

        XCTAssertEqual(snapshot.pending.map(\.payloadID), [valid.payloadID])
        XCTAssertEqual(snapshot.malformedCount, 1)
        XCTAssertEqual(snapshot.futureSchemaCount, 1)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: WordImportSubmissionQueue.directory(
                    .malformed, baseDirectory: fixture.baseDirectory),
                includingPropertiesForKeys: nil
            ).count,
            1
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: WordImportSubmissionQueue.directory(
                    .futureSchema, baseDirectory: fixture.baseDirectory),
                includingPropertiesForKeys: nil
            ).count,
            1
        )
        XCTAssertEqual(
            WordImportSubmissionQueue.attentionMessage(for: snapshot),
            "发现 1 条较新格式的导入记录和 1 条无法读取的导入记录，已分别隔离保存；更新 WordMem 后可恢复较新记录。"
        )
    }

    func testLegacyPendingUserDefaultsArrayMigratesOnePayloadPerFile() throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture) }
        let first = submission()
        var second = submission(source: .translationProvider)
        second.payloadID = UUID()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        fixture.defaults.set(
            try encoder.encode([first, second]),
            forKey: WordImportSubmissionQueue.pendingKey
        )

        let snapshot = try WordImportSubmissionQueue.snapshot(
            baseDirectory: fixture.baseDirectory,
            legacyDefaults: fixture.defaults
        )

        XCTAssertEqual(Set(snapshot.pending.map(\.payloadID)), [first.payloadID, second.payloadID])
        XCTAssertNil(fixture.defaults.data(forKey: WordImportSubmissionQueue.pendingKey))
        XCTAssertNotNil(
            fixture.defaults.data(forKey: WordImportSubmissionQueue.legacyPendingBackupKey)
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: WordImportSubmissionQueue.directory(
                    .pending, baseDirectory: fixture.baseDirectory),
                includingPropertiesForKeys: nil
            ).count,
            2
        )
    }

    func testMaintenanceCoordinatorAllowsOnlyOneOverlappingMigration() async throws {
        let coordinator = WordImportMaintenanceCoordinator()
        var enteredContinuation: AsyncStream<Void>.Continuation?
        let enteredStream = AsyncStream<Void> { enteredContinuation = $0 }
        var releaseContinuation: AsyncStream<Void>.Continuation?
        let releaseStream = AsyncStream<Void> { releaseContinuation = $0 }
        var executionCount = 0

        async let first: Void = coordinator.run {
            executionCount += 1
            enteredContinuation?.yield()
            for await _ in releaseStream { break }
        }

        for await _ in enteredStream { break }
        await coordinator.run {}
        releaseContinuation?.yield()
        await first

        XCTAssertEqual(executionCount, 1)
    }

    func testCrashWindowReplaySkipsCompletePayloadAndRemovesQueueRecord() async throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture) }
        let payload = submission(source: .translationProvider)
        try WordImportSubmissionQueue.append(
            payload,
            baseDirectory: fixture.baseDirectory,
            legacyDefaults: fixture.defaults
        )
        // Simulate a crash after the SwiftData commit but before queue removal.
        _ = try await fixture.repository.importSubmission(payload, using: fixture.dictionary)

        let result = try await WordImportSubmissionMigrator.processPendingSubmissions(
            baseDirectory: fixture.baseDirectory,
            legacyDefaults: fixture.defaults,
            into: fixture.modelContext,
            dictionaryService: fixture.dictionary
        )

        XCTAssertEqual(result.skippedReplayedCount, 1)
        XCTAssertEqual(result.importedPayloadCount, 0)
        XCTAssertEqual(try fixture.modelContext.fetch(FetchDescriptor<WordEntry>()).count, 1)
        XCTAssertEqual(
            try fixture.modelContext.fetch(FetchDescriptor<WordImportContext>()).count, 1)
        XCTAssertTrue(
            try WordImportSubmissionQueue.snapshot(
                baseDirectory: fixture.baseDirectory,
                legacyDefaults: fixture.defaults
            ).pending.isEmpty
        )
    }

    func testWhitespaceOnlyStructuredSubmissionIsRejectedAsEmpty() async throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture) }
        let payload = submission(text: "   ", translation: nil)

        do {
            _ = try await fixture.repository.importSubmission(payload, using: fixture.dictionary)
            XCTFail("Expected whitespace-only submission to fail")
        } catch let error as WordImportError {
            XCTAssertEqual(error, .emptySelection)
        }
        XCTAssertTrue(try fixture.modelContext.fetch(FetchDescriptor<WordEntry>()).isEmpty)
    }

    func testEveryProductionSourceUsesStructuredPayloadIdentityAndContext() async throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture) }
        let sources: [WordImportSource] = [
            .manual, .image, .text, .defaultApp, .shareExtension, .translationProvider,
        ]

        for source in sources {
            let payload = submission(source: source)
            let outcomes = try await fixture.repository.importSubmission(
                payload,
                using: fixture.dictionary
            )
            XCTAssertEqual(outcomes.count, 1)

            let context = try XCTUnwrap(
                fixture.modelContext.fetch(FetchDescriptor<WordImportContext>()).last
            )
            XCTAssertEqual(context.source, source)
            XCTAssertEqual(context.submissionPayloadID, payload.payloadID)
            XCTAssertEqual(context.payloadSchemaVersion, WordImportSubmission.currentSchemaVersion)
            XCTAssertEqual(context.candidatePayloadID, payload.candidates.first?.payloadID)
            XCTAssertEqual(
                context.metadata["candidatePayloadID"],
                payload.candidates.first?.payloadID.uuidString)
            XCTAssertEqual(context.metadata["submittedNormalizedKey"], "run")
            if source == .image {
                XCTAssertEqual(context.imageData, Data([1, 2, 3]))
            }
        }
    }

    func testImportedUserExampleUsesCurrentFieldInsteadOfLegacyField() async throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture) }
        let payload = submission(source: .manual)
        _ = try await fixture.repository.importSubmission(payload, using: fixture.dictionary)

        let entry = try XCTUnwrap(
            fixture.modelContext.fetch(FetchDescriptor<WordEntry>()).first
        )
        XCTAssertEqual(entry.userExample, "My current example.")
        XCTAssertNil(entry.legacyExample)
    }

    func testMetadataOnlySubmissionIdentityIsBackfilledIntoQueryableFields() throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture) }
        let payloadID = UUID()
        let entry = WordEntry(
            originalInput: "run",
            normalizedKey: "run",
            headword: "run"
        )
        let context = WordImportContext(
            entry: entry,
            source: .shareExtension,
            selectedCandidate: "run"
        )
        fixture.modelContext.insert(entry)
        fixture.modelContext.insert(context)
        // Work around the iOS 27 SwiftData insert-registration behavior used by production.
        context.metadata = [
            "payloadID": payloadID.uuidString,
            "payloadSchemaVersion": "1",
        ]
        try fixture.modelContext.save()

        try WordImportContextMigrator.backfillSubmissionIdentity(
            in: fixture.modelContext,
            defaults: fixture.defaults
        )

        XCTAssertEqual(context.submissionPayloadID, payloadID)
        XCTAssertEqual(context.payloadSchemaVersion, 1)
    }
}
