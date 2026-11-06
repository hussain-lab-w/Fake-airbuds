import Foundation
import MediaPlayer

@MainActor
final class MediaLibraryStore: ObservableObject {
    @Published private(set) var playlists: [MPMediaItemCollection] = []
    @Published private(set) var allSongs: [MPMediaItem] = []
    @Published var selectedPlaylistID: MPMediaEntityPersistentID?
    @Published var authorization: MPMediaLibraryAuthorizationStatus = .notDetermined
    @Published var message: String?

    var selectedPlaylist: MPMediaItemCollection? {
        guard let selectedPlaylistID else { return nil }
        return playlists.first { $0.persistentID == selectedPlaylistID }
    }

    func requestAccessAndLoad() async {
        let status = await MPMediaLibrary.requestAuthorization()
        authorization = status
        guard status == .authorized else {
            message = "Allow media library access in Settings."
            return
        }

        let playlistQuery = MPMediaQuery.playlists()
        playlists = playlistQuery.collections ?? []
        if selectedPlaylistID == nil {
            selectedPlaylistID = playlists.first?.persistentID
        }

        // Keep local items with a nil assetURL visible so the UI can explain why they cannot play.
        // Cloud-only items are excluded because this player intentionally handles local files only.
        allSongs = (MPMediaQuery.songs().items ?? [])
            .filter { !$0.isCloudItem }
            .sorted {
                ($0.title ?? "").localizedCaseInsensitiveCompare($1.title ?? "") == .orderedAscending
            }
    }

    func items(in playlist: MPMediaItemCollection?) -> [MPMediaItem] {
        (playlist?.items ?? []).filter { !$0.isCloudItem }
    }

    func playableItems(_ items: [MPMediaItem]) -> [MPMediaItem] {
        items.filter { $0.assetURL != nil }
    }
}
