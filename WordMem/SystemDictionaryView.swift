import SwiftUI
import UIKit

/// Presents the iOS system dictionary definition for a term.
///
/// Wraps `UIReferenceLibraryViewController(term:)`, the public UIKit API for
/// dictionary detail presentation. Check availability first with
/// `UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm:)`; the
/// system downloads dictionary assets on demand, so a term can become
/// available after the user enables dictionaries in Settings.
struct SystemDictionaryView: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(
        _ uiViewController: UIReferenceLibraryViewController,
        context: Context
    ) {}
}
