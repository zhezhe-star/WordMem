import Foundation
import SwiftData

struct WordMemStore {
    let storeURL: URL
    private let defaults: UserDefaults
    private static let resetCompletedKey = "wordmem.nativeStoreV3.resetCompleted"

    static var defaultStoreURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("WordMem", isDirectory: true)
            .appendingPathComponent("wordmem-v3.store")
    }

    init(
        storeURL: URL = WordMemStore.defaultStoreURL,
        defaults: UserDefaults = .standard
    ) {
        self.storeURL = storeURL
        self.defaults = defaults
        Self.performDestructiveReset(to: storeURL, defaults: defaults)
    }

    func makeContainer() throws -> ModelContainer {
        let directory = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let configuration = ModelConfiguration(url: storeURL)
        let schema = Schema([WordEntry.self, WordImportContext.self])
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Destructive, one-time reset authorized by the clean-store plan. No old
    /// word, import, queue default, or migration marker is migrated.
    static func performDestructiveReset(to storeURL: URL, defaults: UserDefaults) {
        guard !defaults.bool(forKey: resetCompletedKey) else { return }
        deleteDatabase(at: storeURL)
        deleteDatabase(at: defaultStoreURL)

        for key in [
            "saved_words",
            "pending_word_import_submissions.v1",
            "did_migrate_standard_saved_words",
            "swiftDataSchemaMigrationCompleted",
            "wordImportContextEntryIDBackfill.v1.completed",
            "wordImportSubmissionIdentityBackfill.v1.completed",
        ] {
            defaults.removeObject(forKey: key)
        }

        defaults.set(true, forKey: resetCompletedKey)
    }

    private static func deleteDatabase(at url: URL) {
        let manager = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            try? manager.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }

        // Exploration-era builds left several store filenames beside the active
        // database. The destructive reset removes every SQLite-backed store file
        // in the app-owned directory; no file is read or migrated.
        let parent = url.deletingLastPathComponent()
        let names = (try? manager.contentsOfDirectory(atPath: parent.path)) ?? []
        for name in names where name.hasSuffix(".store") || name.hasSuffix(".store-shm") || name.hasSuffix(".store-wal") {
            try? manager.removeItem(at: parent.appendingPathComponent(name))
        }
    }
}
