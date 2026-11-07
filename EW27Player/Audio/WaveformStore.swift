import Foundation
import AVFoundation
import Accelerate

@MainActor
final class WaveformStore: ObservableObject {
    @Published private(set) var peaks: [Float] = []
    @Published private(set) var envelope: [Float] = []
    @Published private(set) var bpm: Double?
    @Published private(set) var isLoading = false

    private var task: Task<Void, Never>?
    private var memory: [UInt64: ([Float], [Float])] = [:]

    func load(url: URL?, persistentID: UInt64) {
        task?.cancel()
        peaks = []
        envelope = []
        bpm = nil
        guard let url else { return }
        if let cached = memory[persistentID] {
            peaks = cached.0; envelope = cached.1; bpm = BPMDetector.estimate(envelope: cached.1); return
        }
        if let cached = readDisk(persistentID: persistentID) {
            memory[persistentID] = cached
            peaks = cached.0; envelope = cached.1; bpm = BPMDetector.estimate(envelope: cached.1); return
        }
        isLoading = true
        task = Task.detached(priority: .utility) { [weak self] in
            guard let result = Self.extract(url: url), !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.memory[persistentID] = result
                self.peaks = result.0
                self.envelope = result.1
                self.bpm = BPMDetector.estimate(envelope: result.1)
                self.isLoading = false
                self.writeDisk(result, persistentID: persistentID)
            }
        }
    }

    private nonisolated static func extract(url: URL) -> ([Float], [Float])? {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else { return nil }
        let sampleRate = file.processingFormat.sampleRate
        let totalFrames = Int(file.length)
        let block = 16_384
        let envelopeBlock = max(1, Int(sampleRate / 100))
        var values: [Float] = []
        var envelope: [Float] = []
        var remaining = totalFrames
        while remaining > 0 {
            if Task.isCancelled { return nil }
            let count = min(block, remaining)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(count)) else { break }
            do { try file.read(into: buffer) } catch { return nil }
            guard let channels = buffer.floatChannelData else { break }
            let channelCount = Int(buffer.format.channelCount)
            let frames = Int(buffer.frameLength)
            var mono = Array(repeating: Float.zero, count: frames)
            for channel in 0..<channelCount {
                let samples = Array(UnsafeBufferPointer(start: channels[channel], count: frames))
                vDSP_vadd(mono, 1, samples, 1, &mono, 1, vDSP_Length(frames))
            }
            if channelCount > 1 { vDSP_vsdiv(mono, 1, [Float(channelCount)], &mono, 1, vDSP_Length(frames)) }
            var maxValue: Float = 0
            vDSP_maxmgv(mono, 1, &maxValue, vDSP_Length(frames))
            values.append(maxValue)
            for start in stride(from: 0, to: frames, by: envelopeBlock) {
                let end = min(frames, start + envelopeBlock)
                var rms: Float = 0
                vDSP_rmsqv(Array(mono[start..<end]), 1, &rms, vDSP_Length(end - start))
                envelope.append(rms)
            }
            remaining -= frames
        }
        guard !values.isEmpty else { return nil }
        let outputCount = 240
        var peaks = Array(repeating: Float.zero, count: outputCount)
        for index in 0..<outputCount {
            let start = Int(Double(index) / Double(outputCount) * Double(values.count))
            let end = max(start + 1, Int(Double(index + 1) / Double(outputCount) * Double(values.count)))
            peaks[index] = values[start..<min(end, values.count)].max() ?? 0
        }
        let maxPeak = peaks.max() ?? 1
        if maxPeak > 0 { peaks = peaks.map { $0 / maxPeak } }
        return (peaks, envelope)
    }

    private func cacheURL(_ id: UInt64) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("waveform-\(id).json")
    }

    private func readDisk(persistentID: UInt64) -> ([Float], [Float])? {
        guard let data = try? Data(contentsOf: cacheURL(persistentID)), let value = try? JSONDecoder().decode(CacheValue.self, from: data) else { return nil }
        return (value.peaks, value.envelope)
    }

    private func writeDisk(_ result: ([Float], [Float]), persistentID: UInt64) {
        let value = CacheValue(peaks: result.0, envelope: result.1)
        if let data = try? JSONEncoder().encode(value) { try? data.write(to: cacheURL(persistentID), options: .atomic) }
    }

    private struct CacheValue: Codable { let peaks: [Float]; let envelope: [Float] }
}
