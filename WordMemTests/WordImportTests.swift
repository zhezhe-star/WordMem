import SwiftData
import UIKit
import XCTest
@testable import WordMem

@MainActor
final class WordImportTests: XCTestCase {
    private struct Fixture {
        let modelContext: ModelContext
        let repository: WordbookRepository
        let dictionaryService: BundledDictionaryLookupService
    }

    private func makeFixture() throws -> Fixture {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WordEntry.self,
            WordImportContext.self,
            configurations: configuration
        )
        let modelContext = ModelContext(container)

        return Fixture(
            modelContext: modelContext,
            repository: WordbookRepository(modelContext: modelContext),
            dictionaryService: BundledDictionaryLookupService(
                catalog: DevelopmentSeedDictionaryCatalog.entries
            )
        )
    }

    func testCandidateSplittingKeepsEnglishWordsInOrderAndDeduplicatesByMeaning() {
        let candidates = EnglishWordCandidateSplitter.candidates(
            from: "The cat saw two cats; it didn't blink!"
        )

        XCTAssertEqual(candidates.map(\.text), ["The", "cat", "saw", "two", "cats", "it", "didn't", "blink"])
        XCTAssertEqual(candidates.map(\.normalizedKey), [
            "the", "cat", "saw", "two", "cats", "it", "didnt", "blink",
        ])
    }

    func testCandidateSplittingKeepsHyphenatedCompoundAsOneCandidate() {
        let candidates = EnglishWordCandidateSplitter.candidates(
            from: "A mother-in-law visited Mother-in-Law."
        )

        XCTAssertEqual(candidates.map(\.text), ["A", "mother-in-law", "visited"])
        XCTAssertEqual(candidates.map(\.normalizedKey), ["a", "mother-in-law", "visited"])
    }

    func testSharedChipSelectionDefaultsToNoneAndPreservesSourceOrder() {
        let chips = [
            ImportCandidateChip(id: "the", text: "The", sourceOrder: 0),
            ImportCandidateChip(id: "cat", text: "cat", sourceOrder: 1),
            ImportCandidateChip(id: "ran", text: "ran", sourceOrder: 2),
        ]
        var selection = ImportChipSelection(chips: chips)

        XCTAssertTrue(selection.selectedChips.isEmpty)

        selection.toggle("cat")
        XCTAssertEqual(selection.selectedChips.map(\.id), ["cat"])

        selection.clear()
        XCTAssertTrue(selection.selectedChips.isEmpty)

        selection.selectAll()
        XCTAssertEqual(selection.selectedChips.map(\.id), ["the", "cat", "ran"])
    }

    func testSharedChipSelectionUpdatesSelectedCountAndIsSelected() {
        let chips = [
            ImportCandidateChip(id: "one", text: "one", sourceOrder: 0),
            ImportCandidateChip(id: "two", text: "two", sourceOrder: 1),
        ]
        var selection = ImportChipSelection(chips: chips)

        XCTAssertEqual(selection.selectedCount, 0)
        XCTAssertFalse(selection.isSelected("one"))

        selection.select("one")
        XCTAssertEqual(selection.selectedCount, 1)
        XCTAssertTrue(selection.isSelected("one"))
        XCTAssertFalse(selection.isSelected("two"))
    }

    func testSharedChipSelectionRefreshPreservesSelectionsAndLeavesNewChipsUnselected() {
        let initialChips = [
            ImportCandidateChip(id: "the", text: "The", sourceOrder: 0),
            ImportCandidateChip(id: "cat", text: "cat", sourceOrder: 1),
        ]
        var selection = ImportChipSelection(chips: initialChips)
        selection.select("the")

        let refreshedChips = initialChips + [
            ImportCandidateChip(id: "dog", text: "dog", sourceOrder: 2),
        ]
        selection.updateChips(refreshedChips)

        XCTAssertTrue(selection.isSelected("the"))
        XCTAssertFalse(selection.isSelected("cat"))
        XCTAssertFalse(selection.isSelected("dog"))
        XCTAssertEqual(selection.selectedChips.map(\.id), ["the"])
    }

    func testSharedChipOrganizerGroupsAndSortsBySourceOrder() {
        let chips = [
            ImportCandidateChip(
                id: "second",
                text: "second",
                sourceOrder: 1,
                group: "单词"
            ),
            ImportCandidateChip(
                id: "phrase",
                text: "first second",
                sourceOrder: 0,
                group: "整句"
            ),
            ImportCandidateChip(
                id: "first",
                text: "first",
                sourceOrder: 2,
                group: "单词"
            ),
        ]

        let sections = ImportCandidateOrganizer.sections(from: chips)

        XCTAssertEqual(sections.map(\.title), ["整句", "单词"])
        XCTAssertEqual(sections[0].chips.map(\.id), ["phrase"])
        XCTAssertEqual(sections[1].chips.map(\.id), ["second", "first"])
    }

    func testWordImportCandidatesConvertToStableSourceOrderedChips() {
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        let source = (0..<55)
            .map { "\(letters[$0 / 26])\(letters[$0 % 26])" }
            .joined(separator: " ")
        let candidates = EnglishWordCandidateSplitter.candidates(from: source)

        let chips = ImportCandidateAdapter.chips(from: candidates)
        var selection = ImportChipSelection(chips: chips)

        XCTAssertEqual(chips.count, 55)
        XCTAssertEqual(chips.map(\.sourceOrder), Array(0..<55))
        XCTAssertEqual(chips.map(\.id), candidates.map(\.normalizedKey))
        XCTAssertTrue(selection.selectedChips.isEmpty)
    }

    func testSharedChipSelectionDeduplicatesFirstSeenChipsDeterministically() {
        let duplicatedChips = [
            ImportCandidateChip(id: "cat", text: "cat", sourceOrder: 2),
            ImportCandidateChip(id: "dog", text: "dog", sourceOrder: 3),
            ImportCandidateChip(id: "cat", text: "Cat", sourceOrder: 1),
        ]

        let uniqueChips = ImportCandidateChip.uniquelyIdentified(duplicatedChips)
        var selection = ImportChipSelection(chips: duplicatedChips)
        selection.selectAll()

        XCTAssertEqual(uniqueChips.map(\.id), ["cat", "dog"])
        XCTAssertEqual(uniqueChips.map(\.text), ["cat", "dog"])
        XCTAssertEqual(selection.selectedChips.map(\.id), ["cat", "dog"])
        XCTAssertEqual(selection.selectedChips.map(\.text), ["cat", "dog"])

        selection.updateChips(duplicatedChips)
        XCTAssertEqual(selection.selectedChips.map(\.id), ["cat", "dog"])
        XCTAssertEqual(selection.selectedChips.map(\.text), ["cat", "dog"])
    }

    func testChipAccessibilityLabelCombinesMeaningWithoutVisualChange() {
        XCTAssertEqual(ImportCandidateAccessibility.label(text: "cat", meaning: nil), "cat")
        XCTAssertEqual(ImportCandidateAccessibility.label(text: "cat", meaning: ""), "cat")
        XCTAssertEqual(
            ImportCandidateAccessibility.label(text: "cat", meaning: "猫"),
            "cat，猫"
        )
    }

    func testContextExpansionDetectsLongTextAndTogglesAccessibly() {
        let multiline = (1...7).map { "line \($0)" }.joined(separator: "\n")
        var multilineExpansion = ImportContextExpansion(text: multiline)

        XCTAssertTrue(multilineExpansion.isExpandable)
        XCTAssertFalse(multilineExpansion.isExpanded)
        XCTAssertEqual(multilineExpansion.lineLimit, 5)

        multilineExpansion.toggle()
        XCTAssertTrue(multilineExpansion.isExpanded)
        XCTAssertNil(multilineExpansion.lineLimit)

        let longWrappedText = String(repeating: "word ", count: 48)
        let wrappedExpansion = ImportContextExpansion(text: longWrappedText)
        XCTAssertTrue(wrappedExpansion.isExpandable)

        let shortExpansion = ImportContextExpansion(text: "short context")
        XCTAssertFalse(shortExpansion.isExpandable)
        XCTAssertNil(shortExpansion.lineLimit)
    }

    func testTextBatchImportCreatesSelectedWordsWithSharedSourceSentence() async throws {
        let fixture = try makeFixture()
        let sourceSentence = "The quick brown fox jumps over the lazy dog."

        let outcomes = try await fixture.repository.importWords(
            ["quick", "fox", "quick"],
            source: .text,
            sourceText: sourceSentence,
            using: fixture.dictionaryService
        )

        XCTAssertEqual(outcomes.count, 2)
        XCTAssertEqual(outcomes.map(\.entry.headword), ["quick", "fox"])

        let entries = try fixture.modelContext.fetch(FetchDescriptor<WordEntry>())
        let contexts = try fixture.modelContext.fetch(FetchDescriptor<WordImportContext>())
        XCTAssertEqual(entries.map(\.normalizedKey).sorted(), ["fox", "quick"])
        XCTAssertEqual(contexts.count, 2)
        XCTAssertTrue(contexts.allSatisfy { $0.source == .text })
        XCTAssertTrue(contexts.allSatisfy { $0.sourceText == sourceSentence })
        XCTAssertEqual(
            Set(contexts.map(\.selectedCandidate)),
            ["quick", "fox"]
        )
        XCTAssertEqual(
            Set(contexts.compactMap(\.entryID)),
            Set(outcomes.map(\.entry.id))
        )
    }

    func testLemmaCollisionPreservesPerInputOutcomeSemanticsAndHistory() async throws {
        let fixture = try makeFixture()

        let outcomes = try await fixture.repository.importWords(
            ["run", "running"],
            source: .text,
            sourceText: "I run after running.",
            using: fixture.dictionaryService
        )

        guard case .added = outcomes.first else {
            return XCTFail("Expected first lemma input to be added, got \(String(describing: outcomes.first))")
        }
        guard case .duplicate = outcomes.last else {
            return XCTFail("Expected second lemma input to duplicate, got \(String(describing: outcomes.last))")
        }

        let summary = WordImportSummary(outcomes: outcomes)
        XCTAssertEqual(summary.addedCount, 1)
        XCTAssertEqual(summary.duplicateCount, 1)
        XCTAssertEqual(try fixture.modelContext.fetch(FetchDescriptor<WordEntry>()).count, 1)
        XCTAssertEqual(try fixture.modelContext.fetch(FetchDescriptor<WordImportContext>()).count, 2)
    }

    func testSaveFailureRollsBackEntriesAndImportContexts() async throws {
        let fixture = try makeFixture()
        struct SaveFailure: Error {}
        let repository = WordbookRepository(modelContext: fixture.modelContext) { _ in
            throw SaveFailure()
        }

        do {
            _ = try await repository.importWords(
                ["quick", "fox"],
                source: .text,
                sourceText: "The quick fox.",
                using: fixture.dictionaryService
            )
            XCTFail("Expected save failure")
        } catch {
            guard error is SaveFailure else {
                return XCTFail("Unexpected error \(error)")
            }
        }

        XCTAssertEqual(try fixture.modelContext.fetch(FetchDescriptor<WordEntry>()).count, 0)
        XCTAssertEqual(try fixture.modelContext.fetch(FetchDescriptor<WordImportContext>()).count, 0)
    }

    func testBackfillEntryIDsPreservesLegacyImportContexts() async throws {
        let fixture = try makeFixture()
        let defaultsSuiteName = "WordImportBackfill.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        guard case .added(let entry) = try await fixture.repository.add(
            "run",
            using: fixture.dictionaryService
        ) else {
            return XCTFail("Expected a new word")
        }

        let contexts = try fixture.modelContext.fetch(FetchDescriptor<WordImportContext>())
        let legacyContext = try XCTUnwrap(contexts.first)
        legacyContext.entryID = nil
        try fixture.modelContext.save()

        try WordImportContextMigrator.backfillEntryIDs(
            in: fixture.modelContext,
            defaults: defaults
        )
        let backfilledContext = try XCTUnwrap(
            fixture.modelContext.fetch(FetchDescriptor<WordImportContext>()).first
        )

        XCTAssertEqual(backfilledContext.entryID, entry.id)
        XCTAssertTrue(defaults.bool(forKey: WordImportContextMigrator.backfillCompletedKey))

        backfilledContext.entryID = nil
        try fixture.modelContext.save()
        try WordImportContextMigrator.backfillEntryIDs(
            in: fixture.modelContext,
            defaults: defaults
        )
        XCTAssertNil(backfilledContext.entryID)
    }

    func testBackfillSaveFailureRollsBackAndDoesNotMarkComplete() async throws {
        let fixture = try makeFixture()
        let defaultsSuiteName = "WordImportBackfillFailure.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        struct SaveFailure: Error {}

        guard case .added(let entry) = try await fixture.repository.add(
            "run",
            using: fixture.dictionaryService
        ) else {
            return XCTFail("Expected a new word")
        }

        let context = try XCTUnwrap(
            fixture.modelContext.fetch(FetchDescriptor<WordImportContext>()).first
        )
        context.entryID = nil
        try fixture.modelContext.save()

        do {
            try WordImportContextMigrator.backfillEntryIDs(
                in: fixture.modelContext,
                defaults: defaults
            ) { _ in
                throw SaveFailure()
            }
            XCTFail("Expected backfill save failure")
        } catch {
            guard error is SaveFailure else {
                return XCTFail("Unexpected error \(error)")
            }
        }

        let verificationContext = ModelContext(fixture.modelContext.container)
        let rolledBackContext = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<WordImportContext>()).first
        )
        // The failed backfill must not persist its provisional entryID.
        XCTAssertNil(rolledBackContext.entryID)
        XCTAssertFalse(defaults.bool(forKey: WordImportContextMigrator.backfillCompletedKey))
    }

    func testA0MigrationPlanPreservesContextAndBackfillsEntryID() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WordMemA0Migration-\(UUID().uuidString).store")
        try? FileManager.default.removeItem(at: storeURL)
        try? FileManager.default.removeItem(at: WordMemMigrationPlan.legacyImportPayloadURL)
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: WordMemMigrationPlan.legacyImportPayloadURL)
        }

        let configuration = ModelConfiguration(url: storeURL)
        var legacyContainer: ModelContainer? = try ModelContainer(
            for: Schema(versionedSchema: WordMemSchemaA0.self),
            configurations: configuration
        )
        var migratedEntryID: UUID?
        var expectedImageData: Data?
        do {
            let legacyContext = ModelContext(try XCTUnwrap(legacyContainer))
            let entry = LegacyA0WordEntry(
                id: UUID(),
                originalInput: "run",
                normalizedKey: "run",
                headword: "run",
                phonetic: nil,
                translation: "跑",
                userTranslation: "",
                legacyExample: nil,
                legacyExampleSentence: nil,
                legacyTranslatedExampleSentence: nil,
                senses: [],
                forms: [],
                tags: [],
                lookupStatus: .notFound,
                dictionaryID: nil,
                dictionaryVersion: nil,
                createdAt: .now,
                updatedAt: .now
            )
            let imageData = Data([0x89, 0x50, 0x4e, 0x47])
            migratedEntryID = entry.id
            expectedImageData = imageData
            legacyContext.insert(entry)
            legacyContext.insert(
                LegacyA0WordImportContext(
                    id: UUID(),
                    entry: entry,
                    sourceRawValue: WordImportSource.image.rawValue,
                    sourceText: "Beautiful mountain",
                    selectedCandidate: "mountain",
                    recognizedText: "Beautiful mountain",
                    imageData: imageData,
                    metadata: ["imageByteCount": "\(imageData.count)"],
                    createdAt: .now
                )
            )
            try legacyContext.save()
        }
        legacyContainer = nil

        let migratedContainer = try ModelContainer(
            for: Schema(versionedSchema: WordMemSchemaCurrent.self),
            migrationPlan: WordMemMigrationPlan.self,
            configurations: [configuration]
        )
        let migratedContext = ModelContext(migratedContainer)
        let entries = try migratedContext.fetch(FetchDescriptor<WordEntry>())
        let contexts = try migratedContext.fetch(FetchDescriptor<WordImportContext>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(contexts.count, 1)
        let migratedImport = try XCTUnwrap(contexts.first)
        XCTAssertEqual(migratedImport.entryID, try XCTUnwrap(migratedEntryID))
        XCTAssertEqual(migratedImport.entry?.id, try XCTUnwrap(migratedEntryID))
        XCTAssertEqual(migratedImport.source, .image)
        XCTAssertEqual(migratedImport.sourceText, "Beautiful mountain")
        XCTAssertEqual(migratedImport.selectedCandidate, "mountain")
        XCTAssertEqual(migratedImport.recognizedText, "Beautiful mountain")
        XCTAssertEqual(migratedImport.imageData, expectedImageData)
        XCTAssertEqual(
            migratedImport.metadata["imageByteCount"],
            expectedImageData.map { "\($0.count)" }
        )

        let defaultsSuiteName = "WordImportA0MigrationBackfill.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        migratedImport.entryID = nil
        try migratedContext.save()
        try WordImportContextMigrator.backfillEntryIDs(
            in: migratedContext,
            defaults: defaults
        )
        let verificationContext = ModelContext(migratedContainer)
        let backfilledImport = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<WordImportContext>()).first
        )
        XCTAssertEqual(backfilledImport.entryID, try XCTUnwrap(migratedEntryID))
    }

    func testDuplicateImportAttachesNewContextAndKeepsPriorHistory() async throws {
        let fixture = try makeFixture()
        _ = try await fixture.repository.importWords(
            ["run"],
            source: .text,
            sourceText: "I run every morning.",
            using: fixture.dictionaryService
        )

        let duplicateOutcomes = try await fixture.repository.importWords(
            ["running"],
            source: .defaultApp,
            sourceText: "Running is healthy.",
            using: fixture.dictionaryService
        )

        guard case .duplicate = duplicateOutcomes.first else {
            return XCTFail("Expected lemma lookup to reuse run, got \(String(describing: duplicateOutcomes.first))")
        }

        let entries = try fixture.modelContext.fetch(FetchDescriptor<WordEntry>())
        let contexts = try fixture.modelContext.fetch(FetchDescriptor<WordImportContext>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.normalizedKey, "run")
        XCTAssertEqual(contexts.count, 2)
        XCTAssertEqual(
            Set(contexts.map(\.sourceText)),
            ["I run every morning.", "Running is healthy."]
        )
        XCTAssertEqual(contexts.map(\.source), [.text, .defaultApp])
    }

    func testImageImportStoresImageDataAndRecognizedText() async throws {
        let fixture = try makeFixture()
        let imageData = Data([0x89, 0x50, 0x4e, 0x47])
        let recognizedText = "Beautiful mountain"

        let outcomes = try await fixture.repository.importWords(
            ["beautiful", "mountain"],
            source: .image,
            sourceText: recognizedText,
            imageData: imageData,
            recognizedText: recognizedText,
            using: fixture.dictionaryService
        )

        XCTAssertEqual(outcomes.count, 2)
        let contexts = try fixture.modelContext.fetch(FetchDescriptor<WordImportContext>())
        XCTAssertEqual(contexts.count, 2)
        XCTAssertTrue(contexts.allSatisfy { $0.imageData == imageData })
        XCTAssertTrue(contexts.allSatisfy { $0.recognizedText == recognizedText })
        XCTAssertTrue(contexts.allSatisfy { $0.source == .image })
        XCTAssertTrue(contexts.allSatisfy { $0.metadata["imageByteCount"] == "\(imageData.count)" })
    }

    func testDefaultAppImportPersistsOriginalTextAsContext() async throws {
        let fixture = try makeFixture()
        let originalText = "The user selected serendipity while reading."

        let outcome = try await fixture.repository.addDefaultAppImport(
            "serendipity",
            originalText: originalText,
            using: fixture.dictionaryService
        )

        guard case .added = outcome else {
            return XCTFail("Expected a new default-app word, got \(outcome)")
        }

        let contexts = try fixture.modelContext.fetch(FetchDescriptor<WordImportContext>())
        XCTAssertEqual(contexts.count, 1)
        XCTAssertEqual(contexts.first?.source, .defaultApp)
        XCTAssertEqual(contexts.first?.sourceText, originalText)
    }

    func testManualImportRetainsDictionaryLookupAndRecordsSource() async throws {
        let fixture = try makeFixture()

        let outcome = try await fixture.repository.add("gave", using: fixture.dictionaryService)

        guard case .added(let entry) = outcome else {
            return XCTFail("Expected a new word, got \(outcome)")
        }

        XCTAssertEqual(entry.headword, "give")
        XCTAssertEqual(entry.lookupStatus, .lemmaResolved)
        let contexts = try fixture.modelContext.fetch(FetchDescriptor<WordImportContext>())
        XCTAssertEqual(contexts.count, 1)
        XCTAssertEqual(contexts.first?.source, .manual)
    }

    func testUndoAddAlsoRemovesImportContext() async throws {
        let fixture = try makeFixture()
        guard case .added(let entry) = try await fixture.repository.add(
            "run",
            using: fixture.dictionaryService
        ) else {
            return XCTFail("Expected a new word")
        }

        try fixture.repository.undoAdd(entry)

        XCTAssertEqual(try fixture.modelContext.fetch(FetchDescriptor<WordEntry>()).count, 0)
        XCTAssertEqual(try fixture.modelContext.fetch(FetchDescriptor<WordImportContext>()).count, 0)
    }

    func testDeleteWordsAlsoRemovesImportContexts() async throws {
        let fixture = try makeFixture()
        let outcomes = try await fixture.repository.importWords(
            ["run", "fox"],
            source: .text,
            sourceText: "The fox can run.",
            using: fixture.dictionaryService
        )

        try fixture.repository.deleteWords(outcomes.map(\.entry))

        XCTAssertEqual(try fixture.modelContext.fetch(FetchDescriptor<WordEntry>()).count, 0)
        XCTAssertEqual(try fixture.modelContext.fetch(FetchDescriptor<WordImportContext>()).count, 0)
    }

    func testExistingSwiftDataStoreOpensWithImportContextSchema() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WordMemImportMigration-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let originalConfiguration = ModelConfiguration(url: storeURL)
        let originalContainer = try ModelContainer(
            for: Schema([WordEntry.self]),
            configurations: originalConfiguration
        )
        let originalContext = ModelContext(originalContainer)
        originalContext.insert(
            WordEntry(
                originalInput: "run",
                normalizedKey: "run",
                headword: "run"
            )
        )
        try originalContext.save()

        let upgradedConfiguration = ModelConfiguration(url: storeURL)
        let upgradedContainer = try ModelContainer(
            for: Schema([WordEntry.self, WordImportContext.self]),
            configurations: upgradedConfiguration
        )
        let upgradedContext = ModelContext(upgradedContainer)
        let entries = try upgradedContext.fetch(FetchDescriptor<WordEntry>())

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.normalizedKey, "run")
    }

    func testBatchImportFailureDoesNotLeaveNewWordsOrContexts() async throws {
        let fixture = try makeFixture()
        let failingService = ThrowingDictionaryLookupService()

        do {
            _ = try await fixture.repository.importWords(
                ["quick", "fox"],
                source: .text,
                sourceText: "The quick fox.",
                using: failingService
            )
            XCTFail("Expected import to throw")
        } catch {
            XCTAssertEqual(error as? WordImportTestError, .lookupFailed)
        }

        XCTAssertEqual(try fixture.modelContext.fetch(FetchDescriptor<WordEntry>()).count, 0)
        XCTAssertEqual(try fixture.modelContext.fetch(FetchDescriptor<WordImportContext>()).count, 0)
    }

    func testImportSummaryDescribesAddedAndDuplicateCountsInChinese() {
        let existing = WordEntry(
            originalInput: "run",
            normalizedKey: "run",
            headword: "run"
        )
        let created = WordEntry(
            originalInput: "fox",
            normalizedKey: "fox",
            headword: "fox"
        )
        let summary = WordImportSummary(outcomes: [.added(created), .duplicate(existing)])

        XCTAssertEqual(summary.addedCount, 1)
        XCTAssertEqual(summary.duplicateCount, 1)
        XCTAssertEqual(summary.message, "已添加 1 个单词，已有 1 个单词。")
    }
}

private enum WordImportTestError: Error, Equatable {
    case lookupFailed
}

private struct ThrowingDictionaryLookupService: DictionaryLookupService {
    func lookup(_ rawInput: String) async throws -> DictionaryLookupResult {
        throw WordImportTestError.lookupFailed
    }
}

@MainActor
final class WordImageImportSupportTests: XCTestCase {
    func testImportImageAttributeUsesExternalStorage() throws {
        let attribute = try XCTUnwrap(
            Schema([WordImportContext.self]).entitiesByName["WordImportContext"]?.attributesByName["imageData"]
        )

        XCTAssertTrue(try XCTUnwrap(attribute).options.contains(.externalStorage))
    }

    func testImagePreparationBoundsDimensionsAndPreservesDecodableJPEG() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 3_200, height: 2_000))
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3_200, height: 2_000))

            UIColor.systemRed.setFill()
            for row in 0..<40 {
                context.fill(CGRect(x: 0, y: CGFloat(row * 50), width: 3_200, height: 25))
            }
        }
        let original = try XCTUnwrap(image.jpegData(compressionQuality: 1))

        let prepared = try XCTUnwrap(WordImagePreparer.prepare(original))
        let preparedImage = try XCTUnwrap(UIImage(data: prepared))

        XCTAssertEqual(prepared.prefix(4), Data([0xff, 0xd8, 0xff, 0xe0]))
        XCTAssertLessThanOrEqual(preparedImage.size.width * preparedImage.scale, 2_049)
        XCTAssertLessThanOrEqual(preparedImage.size.height * preparedImage.scale, 1_281)
        XCTAssertLessThan(prepared.count, original.count)
    }

    func testPreparedImageRetainsTextForVision() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2_600, height: 1_200))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2_600, height: 1_200))

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 180, weight: .bold),
                .foregroundColor: UIColor.black,
            ]
            ("Beautiful" as NSString).draw(at: CGPoint(x: 220, y: 300), withAttributes: attributes)
            ("Mountain" as NSString).draw(at: CGPoint(x: 220, y: 650), withAttributes: attributes)
        }
        let prepared = try XCTUnwrap(WordImagePreparer.prepare(image.jpegData(compressionQuality: 1)!))

        let lines = try await VisionTextRecognitionService().recognizeText(in: prepared)
        let text = lines.joined(separator: "\n")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("Beautiful"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("Mountain"))
        XCTAssertLessThanOrEqual(try XCTUnwrap(UIImage(data: prepared)).size.width, 2_048)
        XCTAssertLessThanOrEqual(prepared.count, 2_000_000)
    }

    func testCameraCaptureResultDistinguishesProcessingFailureFromCancellation() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }

        XCTAssertEqual(
            CameraCaptureResult.resolve(image: image, jpegData: Data([1, 2])),
            .success(Data([1, 2]))
        )
        XCTAssertEqual(CameraCaptureResult.resolve(image: nil, jpegData: nil), .cancelled)
        XCTAssertEqual(
            CameraCaptureResult.resolve(image: image, jpegData: nil),
            .processingFailed
        )
    }

    func testCameraAvailabilityProvidesChineseFallbackAndKeepsPhotoLibraryUsable() {
        XCTAssertEqual(
            CameraAvailability.status(isSourceTypeAvailable: true, authorization: .authorized),
            .ready
        )
        XCTAssertEqual(
            CameraAvailability.status(isSourceTypeAvailable: false, authorization: .authorized),
            .unavailable
        )

        let denied = CameraAvailability.status(isSourceTypeAvailable: true, authorization: .denied)
        XCTAssertEqual(denied, .denied)
        XCTAssertFalse(denied.canOpenCamera)
        XCTAssertTrue(denied.fallbackMessage.contains("系统设置"))
        XCTAssertTrue(denied.fallbackMessage.contains("相册"))

        let restricted = CameraAvailability.status(isSourceTypeAvailable: true, authorization: .restricted)
        XCTAssertEqual(restricted, .restricted)
        XCTAssertFalse(restricted.canOpenCamera)
        XCTAssertFalse(restricted.fallbackMessage.isEmpty)

        let unavailable = CameraAvailability.status(isSourceTypeAvailable: false, authorization: .authorized)
        XCTAssertEqual(unavailable.fallbackMessage, "此设备没有可用相机，可以从相册选择包含英文的图片。")
    }
}

@MainActor
final class WordImageProcessingCoordinatorTests: XCTestCase {
    func testStalePhotoCannotCommitOrResetProcessingAfterNewPhotoBegins() {
        let coordinator = WordImageProcessingCoordinator()

        let staleToken = coordinator.begin()
        XCTAssertTrue(coordinator.shouldCommit(staleToken))

        let currentToken = coordinator.begin()
        XCTAssertFalse(coordinator.shouldCommit(staleToken))
        XCTAssertFalse(coordinator.finish(staleToken))
        XCTAssertTrue(coordinator.isProcessing)

        XCTAssertTrue(coordinator.shouldCommit(currentToken))
        XCTAssertTrue(coordinator.finish(currentToken))
        XCTAssertFalse(coordinator.isProcessing)
    }
}

@MainActor
final class ImportCandidateAdvisorTests: XCTestCase {
    private struct FixedLemmaProvider: ImportWordLemmaProviding {
        let lemmas: [String: String]

        func lemma(for word: String, context: String?) async -> String? {
            lemmas[word.lowercased()]
        }
    }

    private struct FixedSpellingSuggester: ImportWordSpellingSuggesting {
        let corrections: [String: String]

        func correction(for word: String) async -> String? {
            // Returning the input models "already spelled correctly"; nil is
            // reserved for live no-suggestion behavior.
            corrections[word.lowercased()] ?? word
        }
    }

    private struct FixedAvailability: ImportWordAvailabilityChecking {
        let available: Set<String>

        func hasDefinition(forTerm term: String) async -> Bool {
            available.contains(term)
        }
    }

    private func makeAdvisor(
        lemmas: [String: String] = [:],
        corrections: [String: String] = [:],
        available: Set<String> = []
    ) -> ImportWordAdvisor {
        ImportWordAdvisor(
            lemmaProvider: FixedLemmaProvider(lemmas: lemmas),
            spellingSuggester: FixedSpellingSuggester(corrections: corrections),
            availability: FixedAvailability(available: available)
        )
    }

    func testAdvisorNormalizesLemmaAndSpellingWhilePreservingSourceOrderAndDedupe() async {
        let source = "Gave gave recieve zq."
        let candidates = EnglishWordCandidateSplitter.candidates(from: source)
        let advisor = makeAdvisor(
            lemmas: ["gave": "give"],
            corrections: ["recieve": "receive"],
            available: ["give", "receive"]
        )

        let chips = await advisor.chips(from: candidates, context: source)

        XCTAssertEqual(chips.map(\.text), ["give", "receive", "zq"])
        XCTAssertEqual(chips.map(\.id), ["give", "receive", "zq"])
        XCTAssertEqual(chips.map(\.sourceOrder), [0, 1, 2])
        XCTAssertEqual(chips[0].advice?.originalText, "Gave")
        XCTAssertEqual(chips[0].advice?.lemma, "give")
        XCTAssertTrue(chips[0].advice?.isLemmaNormalized ?? false)
        XCTAssertEqual(chips[1].advice?.originalText, "recieve")
        XCTAssertEqual(chips[1].advice?.spellingCorrection, "receive")
        XCTAssertTrue(chips[1].advice?.isSpellingCorrected ?? false)
        XCTAssertEqual(chips[0].lemmaBadgeText, "原形 give")
        XCTAssertEqual(chips[1].spellingBadgeText, "拼写纠正 recieve → receive")
    }

    func testAdvisorKeepsUnavailableWordsOutOfDefaultSelectionUntilExplicitRestore() async {
        let source = "zqword"
        let candidates = EnglishWordCandidateSplitter.candidates(from: source)
        let advisor = makeAdvisor(available: [])

        let chips = await advisor.chips(from: candidates, context: source)
        var selection = ImportChipSelection(chips: chips)

        XCTAssertEqual(chips.map(\.text), ["zqword"])
        XCTAssertFalse(chips[0].isImportable)
        XCTAssertEqual(chips[0].availabilityBadgeText, "词典不可用")
        selection.selectAll()
        XCTAssertTrue(selection.selectedChips.isEmpty)

        let restored = chips[0].restoringOriginal()
        selection.updateChips([restored])
        selection.select(restored.id)

        XCTAssertEqual(restored.text, "zqword")
        XCTAssertTrue(restored.isImportable)
        XCTAssertTrue(restored.advice?.isOriginalRestored ?? false)
        XCTAssertEqual(selection.selectedChips.map(\.id), [restored.id])
    }

    func testTranslationPipelineKeepsPhraseContextAndGatesOnlyWordCandidates() async {
        let source = "A recieve day"
        let wordCandidates = EnglishWordCandidateSplitter.candidates(from: source)
        let advisor = makeAdvisor(
            corrections: ["recieve": "receive"],
            available: ["a", "day", "receive"]
        )

        let chips = await ImportCandidatePipeline.translationChips(
            from: source,
            advisor: advisor
        )
        var selection = ImportChipSelection(chips: chips)
        selection.selectAll()

        XCTAssertEqual(chips.first?.text, "A recieve day")
        XCTAssertEqual(chips.dropFirst().map(\.text), ["A", "receive", "day"])
        XCTAssertTrue(chips.first?.isImportable ?? false)
        XCTAssertNil(chips.first?.advice)
        XCTAssertEqual(selection.selectedChips.map(\.id), ["A recieve day", "a", "receive", "day"])

        let payloads = ImportCandidatePipeline.payloads(from: selection.selectedChips)
        XCTAssertEqual(payloads.first?.metadata["phraseContext"], "true")
        XCTAssertEqual(payloads[1].text, "A")
        XCTAssertEqual(payloads[1].metadata["originalWord"], "A")
        XCTAssertEqual(payloads.first { $0.text == "receive" }?.metadata["originalWord"], "recieve")
    }
}
