import UIKit

/// Live availability backed by Apple's iOS system dictionary. This is the only
/// dictionary service in WordMem and it deliberately exposes no content.
struct UIKitSystemDictionaryAuthorizer: SystemDictionaryAuthorizing {
    @MainActor
    func hasDefinition(forTerm term: String) async -> Bool {
        UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term)
    }
}
