import Foundation

struct BPMDetector {
    static func estimate(envelope: [Float], sampleRate: Double = 100) -> Double? {
        guard envelope.count > 80 else { return nil }
        let differences = zip(envelope.dropFirst(), envelope).map { max(0, $0 - $1) }
        let minLag = max(1, Int(sampleRate * 60 / 180))
        let maxLag = min(differences.count - 1, Int(sampleRate * 60 / 60))
        guard minLag < maxLag else { return nil }
        var bestLag = minLag
        var bestScore: Float = -.greatestFiniteMagnitude
        for lag in minLag...maxLag {
            var score: Float = 0
            for index in lag..<differences.count { score += differences[index] * differences[index - lag] }
            if score > bestScore { bestScore = score; bestLag = lag }
        }
        var bpm = 60 * sampleRate / Double(bestLag)
        while bpm < 70 { bpm *= 2 }
        while bpm > 170 { bpm /= 2 }
        return bpm.isFinite ? bpm : nil
    }
}
