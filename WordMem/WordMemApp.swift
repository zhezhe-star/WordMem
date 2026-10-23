import SwiftData
import SwiftUI

@main
struct WordMemApp: App {
    private let store = WordMemStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(try! store.makeContainer())
                .environmentObject(EnglishPronunciationPlayer.shared)
        }
    }
}
