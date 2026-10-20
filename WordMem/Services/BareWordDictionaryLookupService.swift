import Foundation

actor BareWordDictionaryLookupService: DictionaryLookupService {
    func lookup(_ rawInput: String) async throws -> DictionaryLookupResult {
        DictionaryLookupResult(originalInput: rawInput, status: .notFound, entry: nil)
    }
}
