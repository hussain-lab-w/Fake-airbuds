import Foundation
import AVFoundation
import Accelerate

@MainActor
final class SpectrumAnalyzer: ObservableObject {
    @Published private(set) var bars = Array(repeating: Float.zero, count: 32)
    private var installed = false
    private var lastUpdate = Date.distantPast

    func remove(from mixer: AVAudioMixerNode) {
        if installed { mixer.removeTap(onBus: 0); installed = false }
    }

    func install(on mixer: AVAudioMixerNode) {
        mixer.removeTap(onBus: 0)
        installed = false
        let size: AVAudioFrameCount = 2048
        do {
            mixer.installTap(onBus: 0, bufferSize: size, format: mixer.outputFormat(forBus: 0)) { [weak self] buffer, _ in
                guard let channel = buffer.floatChannelData?.pointee else { return }
                let count = min(Int(buffer.frameLength), Int(size))
                guard count > 0 else { return }
                let now = Date()
                guard now.timeIntervalSince(self?.lastUpdate ?? .distantPast) >= 0.05 else { return }
                let samples = Array(UnsafeBufferPointer(start: channel, count: count))
                Task.detached(priority: .utility) {
                    let output = Self.compute(samples: samples, count: 32)
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.lastUpdate = now
                        self.bars = output
                    }
                }
            }
            installed = true
        } catch { installed = false }
    }

    nonisolated private static func compute(samples: [Float], count: Int) -> [Float] {
        let n = 1 << Int(log2(Double(max(2, min(samples.count, 2048)))))
        var input = Array(samples.prefix(n))
        if input.count < n { input += Array(repeating: 0, count: n - input.count) }
        var window = Array(repeating: Float.zero, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        vDSP_vmul(input, 1, window, 1, &input, 1, vDSP_Length(n))
        var real = Array(repeating: Float.zero, count: n / 2)
        var imag = Array(repeating: Float.zero, count: n / 2)
        var magnitudes = Array(repeating: Float.zero, count: n / 2)
        var split = DSPSplitComplex(realp: &real, imagp: &imag)
        let log2n = vDSP_Length(log2(Float(n)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return Array(repeating: 0, count: count) }
        input.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { complex in
                vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(n / 2))
            }
        }
        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
        vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(n / 2))
        vDSP_destroy_fftsetup(setup)
        return (0..<count).map { index in
            let start = max(1, Int(pow(Double(n / 2 - 1), Double(index) / Double(count))))
            let end = max(start + 1, Int(pow(Double(n / 2 - 1), Double(index + 1) / Double(count))))
            let range = magnitudes[min(start, magnitudes.count - 1)..<min(end, magnitudes.count)]
            let value = sqrt(max(0, range.max() ?? 0))
            return max(0, min(1, value / 30))
        }
    }
}
