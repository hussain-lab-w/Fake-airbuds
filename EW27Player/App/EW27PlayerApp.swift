import SwiftUI

@main
struct EW27PlayerApp: App {
    @StateObject private var library = MediaLibraryStore()
    @StateObject private var player = AudioPlayer.shared
    @StateObject private var favorites = FavoritesStore()

    var body: some Scene {
        WindowGroup {
            RebuiltRootView()
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
