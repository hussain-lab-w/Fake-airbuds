import Foundation
import AVFoundation

@MainActor
final class ProcessedAudioExporter {
    static func export(file: AVAudioFile, player: AudioPlayer, progress: @escaping (Double) -> Void) async throws -> URL {
        let sourceFormat = file.processingFormat
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        let varispeed = AVAudioUnitVarispeed()
        let timePitch = AVAudioUnitTimePitch()
        let eq = AVAudioUnitEQ(numberOfBands: 16)
        let reverb = AVAudioUnitReverb()
        let description = AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        let limiter = AVAudioUnitEffect(audioComponentDescription: description)
        [node as AVAudioNode, varispeed, timePitch, eq, reverb, limiter].forEach { engine.attach($0) }
        engine.connect(node, to: varispeed, format: sourceFormat)
        engine.connect(varispeed, to: timePitch, format: sourceFormat)
        engine.connect(timePitch, to: eq, format: sourceFormat)
        engine.connect(eq, to: reverb, format: sourceFormat)
        engine.connect(reverb, to: limiter, format: sourceFormat)
        engine.connect(limiter, to: engine.mainMixerNode, format: sourceFormat)
        varispeed.rate = player.keepPitch ? 1 : player.speed
        timePitch.rate = player.keepPitch ? player.speed : 1
        eq.globalGain = player.preamp
        eq.bypass = !player.eqEnabled
        for index in 0..<min(eq.bands.count, player.eqGains.count) { eq.bands[index].gain = player.eqGains[index] }
        reverb.wetDryMix = player.reverbWet
        if player.reverbMode == "Hall" { reverb.loadFactoryPreset(.largeHall) }
        else if player.reverbMode == "Cathedral" { reverb.loadFactoryPreset(.cathedral) }
        else if player.reverbMode == "Room" { reverb.loadFactoryPreset(.mediumRoom) }
        let renderFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sourceFormat.sampleRate, channels: sourceFormat.channelCount, interleaved: false)!
        try engine.enableManualRenderingMode(.offline, format: renderFormat, maximumFrameCount: 4096)
        node.scheduleFile(file, at: nil)
        try engine.start()
        node.play()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("EW27-Processed-\(UUID().uuidString)")
        let outputURL = base.appendingPathExtension("m4a")
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sourceFormat.sampleRate, AVNumberOfChannelsKey: sourceFormat.channelCount, AVEncoderBitRateKey: 256000]
        let output = try AVAudioFile(forWriting: outputURL, settings: settings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: renderFormat, frameCapacity: 4096) else { throw NSError(domain: "EW27Exporter", code: 1) }
        let total = max(1, Int(Double(file.length) / Double(max(0.25, player.speed))))
        var rendered = 0
        while rendered < total || node.isPlaying {
            let frames = AVAudioFrameCount(min(4096, max(1, total - rendered)))
            switch engine.renderOffline(frames, to: buffer) {
            case .success:
                try output.write(from: buffer)
                rendered += Int(buffer.frameLength)
                progress(min(1, Double(rendered) / Double(total)))
            case .insufficientData:
                rendered = total
            case .cannotDoInCurrentContext:
                continue
            case .error:
                throw NSError(domain: "EW27Exporter", code: 2)
            @unknown default:
                throw NSError(domain: "EW27Exporter", code: 3)
            }
        }
        engine.stop()
        return outputURL
    }
}
