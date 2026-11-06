import AVFoundation
import MediaPlayer
import SwiftUI

@MainActor
enum ProcessedAudioExporter {
    static func render(item: MPMediaItem, speed: Float, keepPitch: Bool, eqGains: [Float], preamp: Float, reverbMode: String, wet: Float) async throws -> URL {
        guard let assetURL = item.assetURL else { throw ExportError.missingAsset }
        let input = try AVAudioFile(forReading: assetURL)
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let varispeed = AVAudioUnitVarispeed()
        let timePitch = AVAudioUnitTimePitch()
        let eq = AVAudioUnitEQ(numberOfBands: 5)
        let reverb = AVAudioUnitReverb()

        if reverbMode != "Off" {
            switch reverbMode {
            case "Room": reverb.loadFactoryPreset(.mediumRoom)
            case "Hall": reverb.loadFactoryPreset(.largeHall)
            case "Cathedral": reverb.loadFactoryPreset(.cathedral)
            default: reverb.loadFactoryPreset(.mediumRoom)
            }
            reverb.wetDryMix = max(0, min(100, wet))
        } else { reverb.wetDryMix = 0 }
        eq.globalGain = preamp
        for index in 0..<min(5, eq.bands.count) {
            eq.bands[index].frequency = [60, 250, 1000, 4000, 12000][index]
            eq.bands[index].gain = eqGains.indices.contains(index) ? eqGains[index] : 0
            eq.bands[index].bypass = false
        }
        if keepPitch {
            varispeed.rate = 1
            timePitch.rate = max(1, min(32_000, 1000 * speed))
            timePitch.pitch = 0
        } else {
            varispeed.rate = max(0.25, min(4, speed))
            timePitch.rate = 1000
        }

        for node in [player as AVAudioNode, varispeed, timePitch, eq, reverb] { engine.attach(node) }
        engine.connect(player, to: varispeed, format: input.processingFormat)
        engine.connect(varispeed, to: timePitch, format: input.processingFormat)
        engine.connect(timePitch, to: eq, format: input.processingFormat)
        engine.connect(eq, to: reverb, format: input.processingFormat)
        engine.connect(reverb, to: engine.mainMixerNode, format: input.processingFormat)

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("EW27-\(UUID().uuidString).m4a")
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: input.processingFormat.sampleRate,
            AVNumberOfChannelsKey: Int(input.processingFormat.channelCount),
            AVEncoderBitRateKey: 192_000
        ]
        let output = try await AVAudioFile(forWriting: outputURL, settings: outputSettings)
        try engine.enableManualRenderingMode(.offline, format: input.processingFormat, maximumFrameCount: 4096)
        player.scheduleFile(input, at: nil)
        try await engine.start()
        player.play()
        let totalFrames = AVAudioFramePosition(Double(input.length) / Double(max(speed, 0.25)))
        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount)!
        var rendered: AVAudioFramePosition = 0
        while rendered < totalFrames {
            let requested = AVAudioFrameCount(min(Int64(buffer.frameCapacity), Int64(totalFrames - rendered)))
            let status = try engine.renderOffline(requested, to: buffer)
            switch status {
            case .success:
                try output.write(from: buffer)
                rendered += AVAudioFramePosition(buffer.frameLength)
            case .insufficientDataFromInputNode:
                continue
            case .cannotDoInCurrentContext:
                continue
            @unknown default:
                throw ExportError.renderFailed
            }
        }
        player.stop()
        engine.stop()
        return outputURL
    }

    enum ExportError: Error {
        case missingAsset
        case renderFailed
    }
}

struct ProcessedAudioExportButton: View {
    @ObservedObject var player: AudioPlayer
    @State private var exportedURL: URL?
    @State private var exporting = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if exporting {
                ProgressView("جارٍ تصدير الصوت…")
            } else if let exportedURL {
                ShareLink(item: exportedURL) { Label("مشاركة الصوت المعالج", systemImage: "square.and.arrow.up") }
            } else {
                Button { Task { await exportCurrentTrack() } } label: {
                    Label("تصدير الصوت المعالج", systemImage: "square.and.arrow.up")
                }
                .disabled(player.currentItem?.assetURL == nil)
            }
        }
        .alert("تعذر التصدير", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("حسنًا", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func exportCurrentTrack() async {
        guard let item = player.currentItem else { return }
        exporting = true
        defer { exporting = false }
        do {
            exportedURL = try await ProcessedAudioExporter.render(item: item, speed: player.speed, keepPitch: player.keepPitch, eqGains: player.eqGains, preamp: player.preamp, reverbMode: player.reverbMode, wet: player.reverbWet)
        } catch { errorMessage = "لا يمكن معالجة هذا الملف الصوتي." }
    }
}
