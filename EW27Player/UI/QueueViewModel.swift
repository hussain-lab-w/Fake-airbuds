import Combine
import MediaPlayer
import UIKit

@MainActor
final class QueueViewModel: ObservableObject {
    @Published private(set) var items: [MPMediaItem]
    @Published private(set) var currentIndex: Int
    @Published private(set) var currentItem: MPMediaItem?
    @Published private(set) var currentArtwork: UIImage?
    @Published private(set) var artworkTint: UIColor?

    private weak var player: AudioPlayer?
    private var playerChanges: AnyCancellable?
    private var itemIDs: [UInt64]
    private var currentID: UInt64?
    private var artworkID: Int?

    init(player: AudioPlayer) {
        self.player = player
        self.items = player.queue
        self.currentIndex = player.currentIndex
        self.currentItem = player.currentItem
        self.currentArtwork = player.currentArtwork
        self.artworkTint = player.artworkTint
        self.itemIDs = player.queue.map(\.persistentID)
        self.currentID = player.currentItem?.persistentID
        self.artworkID = player.currentArtwork?.hash

        playerChanges = player.objectWillChange.sink { [weak self, weak player] _ in
            guard let player else { return }
            Task { @MainActor [weak self] in
                self?.refresh(from: player)
            }
        }
    }

    deinit {
        playerChanges?.cancel()
    }

    func play(at index: Int) {
        guard items.indices.contains(index) else { return }
        player?.jumpToQueue(index: index)
        refreshFromPlayer()
    }

    func remove(at offsets: IndexSet) {
        player?.removeFromQueue(at: offsets)
        refreshFromPlayer()
    }

    func move(from source: IndexSet, to destination: Int) {
        player?.moveQueue(from: source, to: destination)
        refreshFromPlayer()
    }

    private func refreshFromPlayer() {
        guard let player else { return }
        refresh(from: player)
    }

    private func refresh(from player: AudioPlayer) {
        let nextIDs = player.queue.map(\.persistentID)
        let nextCurrentID = player.currentItem?.persistentID
        let nextArtworkID = player.currentArtwork?.hash
        let queueChanged = nextIDs != itemIDs
        let positionChanged = nextCurrentID != currentID || player.currentIndex != currentIndex
        let artworkChanged = nextArtworkID != artworkID

        guard queueChanged || positionChanged || artworkChanged else { return }

        if queueChanged {
            items = player.queue
            itemIDs = nextIDs
        }
        if queueChanged || positionChanged {
            currentIndex = player.currentIndex
            currentItem = player.currentItem
            currentID = nextCurrentID
        }
        if queueChanged || positionChanged || artworkChanged {
            currentArtwork = player.currentArtwork
            artworkTint = player.artworkTint
            artworkID = nextArtworkID
        }
    }
}
