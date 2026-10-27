import Foundation
import WordNetKit

/// Read-only adapter around Open English WordNet. WordMem continues to own
/// `locale + normalizedKey`; this type only supplies third-party content.
struct WordNetKitAuthoritativeDictionaryProvider: AuthoritativeDictionaryAuthorizing {
    private let wordNet: WordNet

    static let shared = WordNetKitAuthoritativeDictionaryProvider()

    init(wordNet: WordNet = WordNet(databaseURL: WordNetKitAuthoritativeDictionaryProvider.databaseURL)) {
        self.wordNet = wordNet
    }

    /// Dynamic linking lets app extensions reuse one framework while the large
    /// Open English WordNet database remains only in the host app bundle.
    private static var databaseURL: URL? {
        if let moduleURL = Bundle.main.url(
            forResource: "WordNetKit_WordNetKitData", withExtension: "bundle"
        ) {
            return moduleURL.appendingPathComponent("wordnet.sqlite")
        }

        let bundleURL = Bundle.main.bundleURL
        let parentName = bundleURL.deletingLastPathComponent().lastPathComponent
        guard parentName == "PlugIns" || parentName == "Extensions" else { return nil }

        let hostAppURL = bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        return hostAppURL
            .appendingPathComponent("WordNetKit_WordNetKitData.bundle")
            .appendingPathComponent("wordnet.sqlite")
    }

    func hasDefinition(forTerm term: String) async -> Bool {
        let key = normalizedKey(term)
        guard !key.isEmpty else { return false }
        return (try? await wordNet.contains(key)) == true
    }

    func entry(forTerm term: String) async throws -> AuthoritativeDictionaryEntry? {
        let key = normalizedKey(term)
        guard !key.isEmpty else { return nil }

        async let metadataTask = wordNet.metadata()
        async let sensesTask = wordNet.senses(for: key)
        async let entriesTask = wordNet.entries(for: key)

        let metadata = try await metadataTask
        let senses = try await sensesTask
        let entries = try await entriesTask
        guard let headword = senses.first?.lemma else { return nil }

        let pronunciations = entries.flatMap(\.pronunciations).reduce(into: [AuthoritativePronunciation]()) { result, value in
            let pronunciation = AuthoritativePronunciation(ipa: value.ipa, variety: value.variety)
            if !result.contains(pronunciation) {
                result.append(pronunciation)
            }
        }

        let mappedSenses = senses.map { sense in
            AuthoritativeDictionarySense(
                id: sense.id.rawValue,
                partOfSpeech: sense.partOfSpeech.displayName,
                definition: sense.definition,
                examples: sense.examples
            )
        }

        return AuthoritativeDictionaryEntry(
            providerID: "org.globalwordnet.oewn",
            providerRevision: metadata.version,
            license: "CC-BY-4.0",
            canonicalKey: key,
            headword: headword,
            pronunciations: pronunciations,
            senses: mappedSenses
        )
    }

    private func normalizedKey(_ term: String) -> String {
        term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
