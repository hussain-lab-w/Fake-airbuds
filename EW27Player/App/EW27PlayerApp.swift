import SwiftUI

@main
struct EW27PlayerApp: App {
    @StateObject private var library = MediaLibraryStore()
    @StateObject private var player = AudioPlayer()
    @StateObject private var favorites = FavoritesStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(favorites)
                .task {
                    await library.requestAccessAndLoad()
                    player.restoreSession()
                }
        }
    }
}
