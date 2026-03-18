import Foundation
import CloudKit

class CloudStorageManager: ObservableObject {
    private let container = CKContainer.default()
    private let privateDatabase: CKDatabase

    @Published var words: [WordData] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    init() {
        privateDatabase = container.privateCloudDatabase
    }

    func saveWord(_ word: WordData) {
        isLoading = true
        errorMessage = nil

        let record = CKRecord(recordType: "Word")
        record["originText"] = word.word
        record["translation"] = word.translation
        record["phonetic"] = word.phonetic ?? ""
        record["createDateString"] = word.createDateString
        record["exampleSentence"] = word.exampleSentence ?? ""
        record["translatedExampleSentence"] = word.translatedExampleSentence ?? ""
        record["example"] = word.example ?? ""

        privateDatabase.save(record) { [weak self] savedRecord, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                } else {
                    self?.words.append(word)
                }
            }
        }
    }

    func fetchWords() {
        isLoading = true
        errorMessage = nil

        let query = CKQuery(recordType: "Word", predicate: NSPredicate(value: true))

        if #available(iOS 15.0, *) {
            privateDatabase.fetch(withQuery: query) { [weak self] result in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    switch result {
                    case .success:
                        // Handle success
                        break
                    case .failure(let error):
                        self?.errorMessage = error.localizedDescription
                    }
                }
            }
        } else {
            // Fallback for iOS 14
            privateDatabase.perform(query, inZoneWith: nil) { [weak self] records, error in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    if let error = error {
                        self?.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}
