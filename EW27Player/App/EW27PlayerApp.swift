import SwiftUI

@main
struct EW27PlayerApp: App {
    @StateObject private var library = MediaLibraryStore()
    @StateObject private var player = AudioPlayer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(player)
                .task { await library.requestAccessAndLoad() }
        }
    }
}
