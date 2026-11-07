import Foundation
import AVFoundation
import Accelerate

final class SpectrumAnalyzer {
    private let queue = DispatchQueue(label: "com.ew27.spectrum", qos: .userInitiated)
    private let lock = NSLock()
    private let fftSize = 2048
    private let barCount = 32
    private var fftSetup: FFTSetup?
    private var window: [Float]
    private var interleaved: [Float]
    private var real: [Float]
    private var imag: [Float]
    private var magnitudes: [Float]
    private var smoothed = Array(repeating: Float.zero, count: 32)
    private var peaks = Array(repeating: Float.zero, count: 32)
    private var lastPublish = Date.distantPast
    private var installed = false

    init() {
        window = Array(repeating: 0, count: fftSize)
        interleaved = Array(repeating: 0, count: fftSize)
        real = Array(repeating: 0, count: fftSize / 2)
        imag = Array(repeating: 0, count: fftSize / 2)
        magnitudes = Array(repeating: 0, count: fftSize / 2)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(fftSize))), FFTRadix(kFFTRadix2))
    }

    deinit {
        if let fftSetup { vDSP_destroy_fftsetup(fftSetup) }
    }

    func remove(from mixer: AVAudioMixerNode) {
        if installed { mixer.removeTap(onBus: 0); installed = false }
    }

    func install(on mixer: AVAudioMixerNode, model: SpectrumModel) {
        mixer.removeTap(onBus: 0)
        installed = false
        let sampleRate = max(1, mixer.outputFormat(forBus: 0).sampleRate)
        mixer.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: mixer.outputFormat(forBus: 0)) { [weak self, weak model] buffer, _ in
            guard let self, let model, let channel = buffer.floatChannelData?.pointee else { return }
            let count = min(Int(buffer.frameLength), self.fftSize)
            guard count > 0 else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: count))
            self.queue.async { [weak self, weak model] in
                guard let self, let model else { return }
                guard let bars = self.process(samples: samples, sampleRate: sampleRate) else { return }
                DispatchQueue.main.async { model.bars = bars }
            }
        }
        installed = true
    }

    private func process(samples: [Float], sampleRate: Double) -> [Float]? {
        lock.lock()
        defer { lock.unlock() }
        guard let fftSetup else { return nil }
        interleaved = Array(repeating: 0, count: fftSize)
        interleaved.replaceSubrange(0..<min(samples.count, fftSize), with: samples.prefix(fftSize))
        vDSP_vmul(interleaved, 1, window, 1, &interleaved, 1, vDSP_Length(fftSize))
        real = Array(repeating: 0, count: fftSize / 2)
        imag = Array(repeating: 0, count: fftSize / 2)
        magnitudes = Array(repeating: 0, count: fftSize / 2)
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                interleaved.withUnsafeBufferPointer { inputPtr in
                    inputPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, vDSP_Length(log2(Float(fftSize))), FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        var output = Array(repeating: Float.zero, count: barCount)
        let nyquist = sampleRate / 2
        for index in 0..<barCount {
            let low = 40.0 * pow(16000.0 / 40.0, Double(index) / Double(barCount))
            let high = 40.0 * pow(16000.0 / 40.0, Double(index + 1) / Double(barCount))
            let start = max(1, min(fftSize / 2 - 1, Int(low / nyquist * Double(fftSize / 2))))
            let end = max(start + 1, min(fftSize / 2, Int(high / nyquist * Double(fftSize / 2))))
            let power = magnitudes[start..<end].reduce(0, +) / Float(max(1, end - start))
            let magnitude = sqrt(max(power, 0)) / Float(fftSize) * 2
            let db = 20 * log10(max(magnitude, 1e-7))
            let tilt = 3 * log2(Float(max(40, (low + high) / 2) / 100.0))
            let normalized = max(0, min(1, (db + tilt + 85) / 70))
            let attack: Float = normalized > smoothed[index] ? 0.6 : 0.12
            smoothed[index] += (normalized - smoothed[index]) * attack
            peaks[index] = max(smoothed[index], peaks[index] - 0.018)
            output[index] = smoothed[index]
        }
        let now = Date()
        guard now.timeIntervalSince(lastPublish) >= (1.0 / 30.0) else { return nil }
        lastPublish = now
        return output
    }
}
