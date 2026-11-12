import UIKit
import MediaPlayer
import CoreImage

final class ArtworkCache {
    static let shared = ArtworkCache()

    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 160
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()
    private static let colorContext = CIContext(options: [.workingColorSpace: NSNull()])

    func image(for persistentID: MPMediaEntityPersistentID, artwork: MPMediaItemArtwork?, size: CGSize) -> UIImage? {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        let key = "\(persistentID)-\(width)x\(height)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = artwork?.image(at: CGSize(width: width, height: height)) else { return nil }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? width * height * 4
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    func averageColor(for image: UIImage?) -> UIColor? {
        guard let image, let ciImage = CIImage(image: image) else { return nil }
        let extent = ciImage.extent
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: ciImage, kCIInputExtentKey: CIVector(cgRect: extent)]),
              let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        Self.colorContext.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let color = UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return UIColor(hue: hue, saturation: min(1, max(0.35, saturation * 1.25)), brightness: min(0.5, max(0.18, brightness)), alpha: 1)
    }
}
