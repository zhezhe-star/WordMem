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
}
