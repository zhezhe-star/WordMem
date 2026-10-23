import Foundation
import SwiftData

struct WordMemStore {
    static let appGroupSuiteName = "group.com.zhezhe.wordmem"
    private static let resetCompletedKey = "wordmem.nativeStoreV3.resetCompleted"

    let storeURL: URL
    private let defaults: UserDefaults
    private let legacyStoreURL: URL?
    private let legacyQueueDirectory: URL?

    static var defaultStoreURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("WordMem", isDirectory: true)
            .appendingPathComponent("wordmem-v3.store")
    }

    static var defaultQueueDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupSuiteName)?
            .appendingPathComponent("WordMemImportQueue", isDirectory: true)
    }

    init(
        storeURL: URL = WordMemStore.defaultStoreURL,
        defaults: UserDefaults = UserDefaults(suiteName: appGroupSuiteName) ?? .standard,
        legacyStoreURL: URL? = WordMemStore.defaultStoreURL,
        legacyQueueDirectory: URL? = WordMemStore.defaultQueueDirectory
    ) {
        self.storeURL = storeURL
        self.defaults = defaults
        self.legacyStoreURL = legacyStoreURL
        self.legacyQueueDirectory = legacyQueueDirectory
        Self.performDestructiveReset(
            to: storeURL,
            defaults: defaults,
            legacyStoreURL: legacyStoreURL,
            legacyQueueDirectory: legacyQueueDirectory
        )
    }

    func makeContainer() throws -> ModelContainer {
        let directory = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let configuration = ModelConfiguration(url: storeURL)
        let schema = Schema([WordEntry.self, WordImportContext.self])
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Destructive, one-time reset authorized by the clean-store plan. No old
    /// word, import queue, quarantine, or migration marker is read or migrated.
    @discardableResult
    static func performDestructiveReset(
        to storeURL: URL,
        defaults: UserDefaults,
        legacyStoreURL: URL?,
        legacyQueueDirectory: URL?
    ) -> Bool {
        guard !defaults.bool(forKey: resetCompletedKey) else { return true }

        var succeeded = deleteDatabase(at: storeURL, removesSiblingStores: storeURL == defaultStoreURL)
        if let legacyStoreURL {
            succeeded = succeeded && deleteDatabase(at: legacyStoreURL, removesSiblingStores: true)
        }

        for key in legacyDefaultKeys {
            defaults.removeObject(forKey: key)
        }

        // Exploration builds used both domains before the app group became the
        // source of truth. Clean the inactive domain only during a production
        // reset so injected test suites never touch unrelated defaults.
        if defaults !== UserDefaults.standard {
            for key in legacyDefaultKeys {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        if let legacyQueueDirectory {
            succeeded = succeeded && removeItem(legacyQueueDirectory)
        }

        guard succeeded else { return false }
        defaults.set(true, forKey: resetCompletedKey)
        return true
    }

    private static var legacyDefaultKeys: [String] {
        [
            "saved_words",
            "pending_word_import_submissions.v1",
            "did_migrate_standard_saved_words",
            "swiftDataSchemaMigrationCompleted",
            "wordImportContextEntryIDBackfill.v1.completed",
            "wordImportSubmissionIdentityBackfill.v1.completed",
        ]
    }

    private static func deleteDatabase(at url: URL, removesSiblingStores: Bool) -> Bool {
        let manager = FileManager.default
        var succeeded = true
        for suffix in ["", "-shm", "-wal"] {
            succeeded = succeeded && removeItem(URL(fileURLWithPath: url.path + suffix))
        }

        // Exploration-era builds left several store filenames beside the active
        // database. Remove every SQLite-backed store file in this app-owned
        // directory; none is read or migrated.
        guard removesSiblingStores else { return succeeded }
        let parent = url.deletingLastPathComponent()
        let names = (try? manager.contentsOfDirectory(atPath: parent.path)) ?? []
        for name in names
        where name.hasSuffix(".store") || name.hasSuffix(".store-shm") || name.hasSuffix(".store-wal") {
            succeeded = succeeded && removeItem(parent.appendingPathComponent(name))
        }
        return succeeded
    }

    private static func removeItem(_ url: URL) -> Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return true }
        do {
            try manager.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }
}
