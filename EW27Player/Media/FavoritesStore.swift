import Foundation
import MediaPlayer

@MainActor
final class FavoritesStore: ObservableObject {
    @Published private(set) var ids: Set<MPMediaEntityPersistentID> = []
    private let key = "ew27.favorite.track.ids.v1"

    init() {
        let values = UserDefaults.standard.array(forKey: key) as? [NSNumber] ?? []
        ids = Set(values.map { $0.uint64Value })
    }

    func contains(_ item: MPMediaItem) -> Bool { ids.contains(item.persistentID) }

    func toggle(_ item: MPMediaItem) {
        if ids.contains(item.persistentID) { ids.remove(item.persistentID) }
        else { ids.insert(item.persistentID) }
        UserDefaults.standard.set(ids.map(NSNumber.init(value:)), forKey: key)
    }
}
