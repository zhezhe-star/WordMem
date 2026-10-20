import SwiftUI
import ExtensionKit
import TranslationUIProvider

@main
class WordMemTranslationProviderExtension: TranslationUIProviderExtension {

    required init() {
    }

    var body: some TranslationUIProviderExtensionScene {
        TranslationUIProviderSelectedTextScene { context in
            TranslationCardView(context: context)
        }
    }
}
