import Foundation
import AVFoundation
import SwiftUI

@MainActor
private final class EffectsState {
    static let shared = EffectsState()
    let reverb = AVAudioUnitReverb()
    var reverbMode = "Off"
    var wet: Float = 30
    var panEnabled = false
    var panRate: Double = 0.2
    var phase: Double = 0
    var panTimer: Timer?
    var sleepTimer: Timer?
    var sleepDeadline: Date?
    var fadeTimer: Timer?
    var loopTimer: Timer?
    var loopA: TimeInterval?
    var loopB: TimeInterval?
    var crossfadeDuration: Double = 0
    var savedPan: Float = 0
    var presets: [String: AudioEffectPreset] = [:]
    var lastTrackID: UInt64?
}

struct AudioEffectPreset: Codable, Identifiable {
    var id: String { name }
    var name: String
    var gains: [Float]
    var preamp: Float
    var speed: Float
    var reverbMode: String
    var wet: Float
}

@MainActor
extension AudioPlayer {
    var reverbMode: String { EffectsState.shared.reverbMode }
    var reverbWet: Float { EffectsState.shared.wet }
    var eightDEnabled: Bool { EffectsState.shared.panEnabled }
    var eightDSpeed: Double { EffectsState.shared.panRate }
    var sleepRemaining: TimeInterval? { EffectsState.shared.sleepDeadline.map { max(0, $0.timeIntervalSinceNow) } }
    var crossfadeSeconds: Double { EffectsState.shared.crossfadeDuration }
    var abLoopStart: TimeInterval? { EffectsState.shared.loopA }
    var abLoopEnd: TimeInterval? { EffectsState.shared.loopB }
    var customEffectPresets: [AudioEffectPreset] { EffectsState.shared.presets.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }

    func setReverb(mode: String, wet: Float? = nil) {
        let state = EffectsState.shared
        state.reverbMode = mode
        if let wet { state.wet = max(0, min(100, wet)) }
        if !engine.attachedNodes.contains(state.reverb) { engine.attach(state.reverb) }
        if mode == "Off" {
            state.reverb.loadFactoryPreset(.mediumRoom)
            state.reverb.wetDryMix = 0
        } else {
            switch mode {
            case "Room": state.reverb.loadFactoryPreset(.mediumRoom)
            case "Hall": state.reverb.loadFactoryPreset(.largeHall)
            case "Cathedral": state.reverb.loadFactoryPreset(.cathedral)
            default: state.reverb.loadFactoryPreset(.mediumRoom)
            }
            state.reverb.wetDryMix = state.wet
        }
        if engine.isRunning {
            engine.stop()
            engine.disconnectNodeOutput(eq)
            engine.disconnectNodeOutput(state.reverb)
            engine.connect(eq, to: state.reverb, format: nil)
            engine.connect(state.reverb, to: limiter, format: nil)
            try? engine.start()
        }
        objectWillChange.send()
        storeEffectsForRoute()
    }

    func setReverbWet(_ wet: Float) { setReverb(mode: reverbMode, wet: wet) }

    func setEightD(enabled: Bool, speed: Double? = nil) {
        let state = EffectsState.shared
        state.panEnabled = enabled
        if let speed { state.panRate = max(0.03, min(1.5, speed)) }
        state.panTimer?.invalidate()
        if enabled {
            state.panTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
                Task { @MainActor in
                    guard let self else { timer.invalidate(); return }
                    let s = EffectsState.shared
                    s.phase += 2 * .pi * s.panRate / 60
                    self.playerNode.pan = Float(sin(s.phase))
                }
            }
        } else { playerNode.pan = 0 }
        objectWillChange.send()
    }

    func setEightDSpeed(_ value: Double) { setEightD(enabled: eightDEnabled, speed: value) }

    func setCrossfade(_ seconds: Double) {
        EffectsState.shared.crossfadeDuration = max(0, min(12, seconds))
        UserDefaults.standard.set(EffectsState.shared.crossfadeDuration, forKey: "ew27.crossfade.seconds")
        objectWillChange.send()
    }

    func setLoopA() {
        EffectsState.shared.loopA = elapsed
        if let b = EffectsState.shared.loopB, b <= elapsed { EffectsState.shared.loopB = nil }
        startLoopMonitor()
        objectWillChange.send()
    }

    func setLoopB() {
        guard let a = EffectsState.shared.loopA, elapsed > a else { return }
        EffectsState.shared.loopB = elapsed
        startLoopMonitor()
        objectWillChange.send()
    }

    func clearABLoop() {
        EffectsState.shared.loopA = nil
        EffectsState.shared.loopB = nil
        EffectsState.shared.loopTimer?.invalidate()
        EffectsState.shared.loopTimer = nil
        objectWillChange.send()
    }

    func startSleepTimer(minutes: Int) {
        let state = EffectsState.shared
        state.sleepTimer?.invalidate()
        state.fadeTimer?.invalidate()
        guard minutes > 0 else { state.sleepDeadline = nil; objectWillChange.send(); return }
        state.sleepDeadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
        state.sleepTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fadeOutAndPause() }
        }
        objectWillChange.send()
    }

    func startCustomSleepTimer(seconds: Int) { startSleepTimer(minutes: max(1, Int(ceil(Double(seconds) / 60)))) }

    func applySlowedReverbPreset() {
        setSpeed(0.85)
        setReverb(mode: "Hall", wet: 30)
    }

    func saveEffectPreset(named name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        EffectsState.shared.presets[clean] = AudioEffectPreset(name: clean, gains: eqGains, preamp: preamp, speed: speed, reverbMode: reverbMode, wet: reverbWet)
        persistPresets()
        objectWillChange.send()
    }

    func applyEffectPreset(named name: String) {
        guard let preset = EffectsState.shared.presets[name] else { return }
        eqGains = preset.gains
        preamp = preset.preamp
        applyEQSettingsForEffects()
        setSpeed(preset.speed)
        setReverb(mode: preset.reverbMode, wet: preset.wet)
        objectWillChange.send()
    }

    func deleteEffectPreset(named name: String) {
        EffectsState.shared.presets.removeValue(forKey: name)
        persistPresets()
        objectWillChange.send()
    }

    func renameEffectPreset(from oldName: String, to newName: String) {
        guard let preset = EffectsState.shared.presets.removeValue(forKey: oldName) else { return }
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { EffectsState.shared.presets[oldName] = preset; return }
        var renamed = preset
        renamed.name = clean
        EffectsState.shared.presets[clean] = renamed
        persistPresets()
        objectWillChange.send()
    }

    private func fadeOutAndPause() {
        let state = EffectsState.shared
        state.sleepTimer?.invalidate()
        state.sleepTimer = nil
        state.sleepDeadline = nil
        state.fadeTimer?.invalidate()
        let startVolume = playerNode.volume
        let start = Date()
        state.fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                let fraction = min(1, Date().timeIntervalSince(start) / 10)
                self.playerNode.volume = startVolume * Float(1 - fraction)
                if fraction >= 1 {
                    timer.invalidate()
                    state.fadeTimer = nil
                    self.pause()
                    self.playerNode.volume = 1
                    self.objectWillChange.send()
                }
            }
        }
        objectWillChange.send()
    }

    private func startLoopMonitor() {
        let state = EffectsState.shared
        state.loopTimer?.invalidate()
        state.loopTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                let s = EffectsState.shared
                if let a = s.loopA, let b = s.loopB, self.elapsed >= b { self.seek(to: a) }
            }
        }
    }

    private func persistPresets() {
        if let data = try? JSONEncoder().encode(EffectsState.shared.presets) {
            UserDefaults.standard.set(data, forKey: "ew27.custom.effect.presets.v1")
        }
    }

    private func storeEffectsForRoute() {
        let map = UserDefaults.standard.dictionary(forKey: "ew27.effects.byRoute.v1") as? [String: [String: Any]] ?? [:]
        var updated = map
        updated[routeName] = ["mode": reverbMode, "wet": Double(reverbWet)]
        UserDefaults.standard.set(updated, forKey: "ew27.effects.byRoute.v1")
    }

    private func applyEQSettingsForEffects() {
        for index in eq.bands.indices where index < eqGains.count { eq.bands[index].gain = eqGains[index] }
        eq.globalGain = preamp
    }
}

struct AudioEffectsSection: View {
    @ObservedObject var player: AudioPlayer
    @State private var presetName = ""
    @State private var sleepMinutes = 30

    var body: some View {
        Section("المؤثرات والتشغيل") {
            Picker("Reverb", selection: Binding(get: { player.reverbMode }, set: { player.setReverb(mode: $0) })) {
                Text("Off").tag("Off")
                Text("Room").tag("Room")
                Text("Hall").tag("Hall")
                Text("Cathedral").tag("Cathedral")
            }
            Slider(value: Binding(get: { Double(player.reverbWet) }, set: { player.setReverbWet(Float($0)) }), in: 0...100)
            Button("Slowed + Reverb") { player.applySlowedReverbPreset() }
            Toggle("8D Auto-pan", isOn: Binding(get: { player.eightDEnabled }, set: { player.setEightD(enabled: $0) }))
            HStack {
                Text("8D speed")
                Slider(value: Binding(get: { player.eightDSpeed }, set: { player.setEightDSpeed($0) }), in: 0.03...1.5)
            }
            Picker("Sleep timer", selection: $sleepMinutes) {
                Text("Off").tag(0)
                Text("15 min").tag(15)
                Text("30 min").tag(30)
                Text("60 min").tag(60)
            }
            .onChange(of: sleepMinutes) { _, value in player.startSleepTimer(minutes: value) }
            if let remaining = player.sleepRemaining {
                Text(String(format: "Sleep in %.0f sec", remaining)).font(.caption)
            }
            HStack {
                Text("Crossfade")
                Slider(value: Binding(get: { player.crossfadeSeconds }, set: { player.setCrossfade($0) }), in: 0...12)
                Text(String(format: "%.0fs", player.crossfadeSeconds)).font(.caption.monospacedDigit())
            }
            HStack {
                Button("A: mark") { player.setLoopA() }
                Button("B: mark") { player.setLoopB() }
                Button("Clear A-B") { player.clearABLoop() }
            }
            HStack {
                TextField("Preset name", text: $presetName)
                Button("Save") { player.saveEffectPreset(named: presetName); presetName = "" }
            }
            ForEach(player.customEffectPresets) { preset in
                HStack {
                    Button(preset.name) { player.applyEffectPreset(named: preset.name) }
                    Spacer()
                    Button("Delete", role: .destructive) { player.deleteEffectPreset(named: preset.name) }
                }
            }
        }
    }
}
