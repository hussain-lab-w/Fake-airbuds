import UIKit
import MediaPlayer

final class ArtworkCache {
    static let shared = ArtworkCache()

    private let cache = NSCache<NSNumber, UIImage>()

    func image(for persistentID: MPMediaEntityPersistentID, artwork: MPMediaItemArtwork?, size: CGSize) -> UIImage? {
        let key = NSNumber(value: persistentID)
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = artwork?.image(at: size) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
