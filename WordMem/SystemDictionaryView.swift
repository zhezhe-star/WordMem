import SwiftUI
import UIKit

enum SystemDictionaryPresentation {
    static func canPresent(_ term: String) -> Bool {
        UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term)
    }
}

struct SystemDictionaryView: View {
    let term: String

    var body: some View {
        Group {
            if SystemDictionaryPresentation.canPresent(term) {
                SystemDictionaryRepresentable(term: term)
            } else {
                ContentUnavailableView(
                    "系统词典未收录",
                    systemImage: "character.book.closed",
                    description: Text("请在 iOS 设置中下载英语词典后重试。")
                )
            }
        }
        .presentationDetents([.medium])
    }
}

private struct SystemDictionaryRepresentable: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}
}
