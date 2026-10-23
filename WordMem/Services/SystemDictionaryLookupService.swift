import Foundation
import UIKit

/// Seam over `UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm:)`
/// so lookup behavior is testable without the live system dictionary.
protocol SystemDictionaryAvailabilityProviding: Sendable {
    func hasDefinition(forTerm term: String) async -> Bool
}

/// Live availability backed by the iOS system dictionary.
///
/// `UIReferenceLibraryViewController` is `@MainActor`-isolated in the modern
/// SDK, so the public UIKit query runs on the main actor. The first query may
/// block briefly while the system loads its dictionary database; later queries
/// are cheap.
extension UIKitSystemDictionaryAvailability: ImportWordAvailabilityChecking {}

struct UIKitSystemDictionaryAvailability: SystemDictionaryAvailabilityProviding {
    @MainActor
    func hasDefinition(forTerm term: String) async -> Bool {
        UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term)
    }
}

/// Runtime dictionary lookup backed by the iOS system dictionary.
///
/// The system dictionary only exposes availability and a presentation UI; it
/// does not vend definition text, phonetics, or word forms programmatically.
/// Lookups therefore produce key-only `DictionaryEntry` values: the wordbook
/// keeps a word key list and defers authoritative definitions and
/// pronunciations to `UIReferenceLibraryViewController(term:)` at presentation
/// time. `LookupStatus.enriched` now means "the system dictionary has a
/// definition for this key".
struct SystemDictionaryLookupService: DictionaryLookupService {
    /// Marker stored on entries whose source of truth is the system dictionary.
    static let dictionaryVersion = "system-dictionary"

    var availability: any SystemDictionaryAvailabilityProviding =
        UIKitSystemDictionaryAvailability()

    init(availability: (any SystemDictionaryAvailabilityProviding)? = nil) {
        if let availability {
            self.availability = availability
        }
    }

    func lookup(_ rawInput: String) async throws -> DictionaryLookupResult {
        let key = WordInputNormalizer.normalizedKey(from: rawInput)
        guard !key.isEmpty else {
            return DictionaryLookupResult(originalInput: rawInput, status: .notFound, entry: nil)
        }

        let hasDefinition = await availability.hasDefinition(forTerm: key)
        return DictionaryLookupResult(
            originalInput: rawInput,
            status: hasDefinition ? .enriched : .notFound,
            entry: keyOnlyEntry(normalizedKey: key)
        )
    }

    private func keyOnlyEntry(normalizedKey key: String) -> DictionaryEntry {
        DictionaryEntry(
            id: "system.\(key)",
            headword: key,
            normalizedKey: key,
            phonetic: nil,
            senses: [],
            forms: [],
            tags: [],
            frequencyRank: nil,
            dictionaryVersion: Self.dictionaryVersion
        )
    }
}
