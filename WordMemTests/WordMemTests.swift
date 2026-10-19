import XCTest
@testable import WordMem

final class WordMemTests: XCTestCase {
    func testAddWordPersistsAcrossStorageInstances() {
        let suiteName = "WordMemTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)
        defer { defaults?.removePersistentDomain(forName: suiteName) }

        let manager = LocalStorageManager(defaults: defaults)
        let word = WordData(
            word: "serendipity",
            translation: "意外发现新事物的能力",
            phonetic: "/ˌser.ənˈdɪp.ə.ti/",
            exampleSentence: "Finding this café was pure serendipity."
        )

        manager.addWord(word)
        let reloadedManager = LocalStorageManager(defaults: defaults)

        XCTAssertEqual(reloadedManager.words.count, 1)
        XCTAssertEqual(reloadedManager.words.first?.word, "serendipity")
        XCTAssertEqual(reloadedManager.words.first?.translation, "意外发现新事物的能力")
        XCTAssertEqual(reloadedManager.words.first?.phonetic, "/ˌser.ənˈdɪp.ə.ti/")
        XCTAssertEqual(
            reloadedManager.words.first?.exampleSentence,
            "Finding this café was pure serendipity."
        )
    }

    func testAppGroupPersistenceStoresDataInInjectedSuite() throws {
        let suiteName = "WordMemTests.persistence.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = LocalStorageManager(defaults: defaults)
        let word = WordData(
            word: "resilience",
            translation: "韧性；复原力",
            note: "Remember the bamboo bending in the storm."
        )

        manager.addWord(word)

        let persistedData = try XCTUnwrap(defaults.data(forKey: "saved_words"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let persistedWords = try decoder.decode([WordData].self, from: persistedData)
        XCTAssertEqual(persistedWords.count, 1)
        XCTAssertEqual(persistedWords.first?.word, "resilience")
        XCTAssertEqual(persistedWords.first?.note, "Remember the bamboo bending in the storm.")

        let reloadedManager = LocalStorageManager(defaults: defaults)
        XCTAssertEqual(reloadedManager.words.first?.id, word.id)
    }

    func testLegacyStandardDefaultsMigrateOnceIntoAppGroupSuite() throws {
        let legacySuiteName = "WordMemTests.legacy.\(UUID().uuidString)"
        let appGroupSuiteName = "WordMemTests.appgroup.\(UUID().uuidString)"
        let legacyDefaults = try XCTUnwrap(UserDefaults(suiteName: legacySuiteName))
        let appGroupDefaults = try XCTUnwrap(UserDefaults(suiteName: appGroupSuiteName))
        defer {
            legacyDefaults.removePersistentDomain(forName: legacySuiteName)
            appGroupDefaults.removePersistentDomain(forName: appGroupSuiteName)
        }

        let legacyWord = WordData(
            word: "serendipity",
            translation: "意外发现新事物的能力",
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let legacyData = try encoder.encode([legacyWord])
        legacyDefaults.set(legacyData, forKey: "saved_words")

        let manager = LocalStorageManager(
            defaults: appGroupDefaults,
            legacyDefaults: legacyDefaults
        )

        XCTAssertEqual(manager.words.count, 1)
        XCTAssertEqual(manager.words.first?.id, legacyWord.id)
        XCTAssertEqual(appGroupDefaults.data(forKey: "saved_words"), legacyData)
        XCTAssertTrue(appGroupDefaults.bool(forKey: LocalStorageManager.migrationCompletedKey))

        let changedLegacyData = Data("changed".utf8)
        legacyDefaults.set(changedLegacyData, forKey: "saved_words")
        let reloadedManager = LocalStorageManager(
            defaults: appGroupDefaults,
            legacyDefaults: legacyDefaults
        )

        XCTAssertEqual(reloadedManager.words.count, 1)
        XCTAssertEqual(reloadedManager.words.first?.id, legacyWord.id)
        XCTAssertEqual(appGroupDefaults.data(forKey: "saved_words"), legacyData)
    }

    func testDecodingPreservesBackwardCompatibleJSONAndOptionalNote() throws {
        let json = """
        [
          {
            "originText": "momentum",
            "translation": "动力；势头"
          },
          {
            "originText": "threshold",
            "translation": "门槛；阈值",
            "note": "Crossed the finishing threshold."
          }
        ]
        """

        let words = try JSONDecoder().decode([WordData].self, from: Data(json.utf8))

        XCTAssertEqual(words.count, 2)
        XCTAssertNil(words[0].note)
        XCTAssertTrue(words[0].createDateString.isEmpty)
        XCTAssertEqual(words[1].word, "threshold")
        XCTAssertEqual(words[1].note, "Crossed the finishing threshold.")
    }
}
