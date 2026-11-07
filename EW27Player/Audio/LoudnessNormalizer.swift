import Foundation
import AVFoundation
import Accelerate

final class LoudnessNormalizer {
    private static var cache: [UInt64: Float] = [:]
    private static let lock = NSLock()

    static func gain(for url: URL, persistentID: UInt64, completion: @escaping (Float) -> Void) {
        lock.lock(); let cached = cache[persistentID]; lock.unlock()
        if let cached { completion(cached); return }
        DispatchQueue.global(qos: .utility).async {
            let result = analyze(url: url)
            lock.lock(); cache[persistentID] = result; lock.unlock()
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func analyze(_ url: URL) -> Float {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { return 0 }
        let sampleRate = file.processingFormat.sampleRate
        let window = AVAudioFramePosition(min(file.length, AVAudioFramePosition(sampleRate * 8)))
        let start = max(0, (file.length - window) / 2)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(window)) else { return 0 }
        file.framePosition = start
        do { try file.read(into: buffer, frameCount: AVAudioFrameCount(window)) } catch { return 0 }
        guard let channel = buffer.floatChannelData?.pointee else { return 0 }
        var rms: Float = 0
        vDSP_rmsqv(channel, 1, &rms, vDSP_Length(buffer.frameLength))
        let db = 20 * log10(max(rms, 1e-7))
        return max(-10, min(6, -16 - db))
    }
}
