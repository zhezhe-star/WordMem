import Foundation
import SwiftUI

final class LocalStorageManager: ObservableObject {
    static let appGroupSuiteName = "group.com.zhezhe.wordmem"

    private let userDefaults: UserDefaults

    @Published var isLoading = false
    @Published var errorMessage: String?

    init(defaults: UserDefaults? = nil) {
        self.userDefaults = defaults ?? UserDefaults(suiteName: Self.appGroupSuiteName) ?? .standard
        loadWords()
    }

    func loadWords() {
        isLoading = false
        errorMessage = nil
    }

    @discardableResult
    func appendSubmission(_ submission: WordImportSubmission) -> Bool {
        do {
            try WordImportSubmissionQueue.append(submission)
            errorMessage = nil
            return true
        } catch {
            errorMessage = "保存导入记录失败，请重试。"
            return false
        }
    }

    func loadSubmissions() -> [WordImportSubmission] {
        WordImportSubmissionQueue.load()
    }

    func removeSubmissions(payloadIDs: Set<UUID>) {
        try? WordImportSubmissionQueue.remove(payloadIDs)
    }

    func queueSnapshot() -> WordImportQueueSnapshot {
        (try? WordImportSubmissionQueue.snapshot()) ?? WordImportQueueSnapshot(pending: [], malformedCount: 0, futureSchemaCount: 0)
    }
}

extension LocalStorageManager: WordImportSubmissionStoring {
    var persistenceMessage: String? { errorMessage }
}
