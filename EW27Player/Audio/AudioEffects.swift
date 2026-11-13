import Foundation
import AVFoundation
import SwiftUI

@MainActor
private final class EffectsState {
    static let shared = EffectsState()
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

private struct BuiltInAudioProfile: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let preset: AudioPlayer.Preset
    let reverb: String
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
        if mode == "Off" {
            reverb.wetDryMix = 0
        } else {
            switch mode {
            case "Room": reverb.loadFactoryPreset(.mediumRoom)
            case "Hall": reverb.loadFactoryPreset(.largeHall)
            case "Cathedral": reverb.loadFactoryPreset(.cathedral)
            default: reverb.loadFactoryPreset(.mediumRoom)
            }
            reverb.wetDryMix = state.wet
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
            state.panTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
                Task { @MainActor in
                    guard let self else { timer.invalidate(); return }
                    let s = EffectsState.shared
                    s.phase += 2 * .pi * s.panRate / 30
                    self.panMixer.pan = Float(sin(s.phase))
                }
            }
        } else { panMixer.pan = 0 }
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
        let startVolume = engine.mainMixerNode.outputVolume
        let start = Date()
        state.fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                let fraction = min(1, Date().timeIntervalSince(start) / 10)
                self.engine.mainMixerNode.outputVolume = startVolume * Float(1 - fraction)
                if fraction >= 1 {
                    timer.invalidate()
                    state.fadeTimer = nil
                    self.pause()
                    self.engine.mainMixerNode.outputVolume = 1
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
    @State private var spatialExpanded = true
    @State private var playbackExpanded = false
    @State private var presetsExpanded = false

    private let builtInProfiles: [BuiltInAudioProfile] = [
        BuiltInAudioProfile(id: "balanced", title: "Balanced", subtitle: "Natural", icon: "waveform", preset: .flat, reverb: "Off"),
        BuiltInAudioProfile(id: "bass", title: "Bass", subtitle: "Deeper low end", icon: "speaker.wave.3.fill", preset: .bassBoost, reverb: "Off"),
        BuiltInAudioProfile(id: "vocal", title: "Vocal", subtitle: "Clear voices", icon: "mic.fill", preset: .vocal, reverb: "Off"),
        BuiltInAudioProfile(id: "bright", title: "Bright", subtitle: "More detail", icon: "sparkles", preset: .treble, reverb: "Off"),
        BuiltInAudioProfile(id: "cinema", title: "Cinema", subtitle: "Wide space", icon: "film", preset: .vocal, reverb: "Hall")
    ]

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                profileStrip
                Divider().overlay(.white.opacity(0.08))
                DisclosureGroup(isExpanded: $spatialExpanded) {
                    spatialControls
                        .padding(.top, 8)
                } label: {
                    studioDisclosureLabel("Spatial", icon: "dot.radiowaves.left.and.right", detail: spatialDetail)
                }
                .tint(.cyan)
                Divider().overlay(.white.opacity(0.08))
                DisclosureGroup(isExpanded: $playbackExpanded) {
                    playbackControls
                        .padding(.top, 8)
                } label: {
                    studioDisclosureLabel("Playback tools", icon: "waveform.path", detail: playbackDetail)
                }
                .tint(.cyan)
                Divider().overlay(.white.opacity(0.08))
                DisclosureGroup(isExpanded: $presetsExpanded) {
                    savedPresetsControls
                        .padding(.top, 8)
                } label: {
                    studioDisclosureLabel("Saved profiles", icon: "square.stack.3d.up", detail: player.customEffectPresets.isEmpty ? "None yet" : "\(player.customEffectPresets.count) saved")
                }
                .tint(.cyan)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ew27Card(prominent: true)
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 12, trailing: 12))
            .listRowBackground(Color.clear)
        } header: {
            EW27SectionLabel("Sound design", systemImage: "slider.horizontal.3")
        }
    }

    private var profileStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ACTIVE PROFILE")
                        .font(.caption2.weight(.bold))
                        .tracking(1.3)
                        .foregroundStyle(EW27Design.cyan)
                    Text(player.selectedPreset.rawValue)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Text(player.eqEnabled ? "EQ ON" : "BYPASSED")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(player.eqEnabled ? .green : .white.opacity(0.42))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(builtInProfiles) { profile in
                        let selected = player.selectedPreset == profile.preset && player.reverbMode == profile.reverb
                        Button {
                            player.applyPreset(profile.preset)
                            player.setReverb(mode: profile.reverb)
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: profile.icon)
                                    .font(.caption.weight(.semibold))
                                Text(profile.title)
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(selected ? Color.black : Color.white.opacity(0.76))
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(selected ? Color.cyan : Color.white.opacity(0.07), in: Capsule())
                            .overlay(Capsule().stroke(selected ? Color.cyan.opacity(0.9) : Color.white.opacity(0.08), lineWidth: 1))
                        }
                        .buttonStyle(MusicPressStyle())
                        .accessibilityLabel("Audio profile \(profile.title)")
                        .accessibilityHint(profile.subtitle)
                    }
                }
            }
        }
    }

    private var spatialDetail: String {
        if player.eightDEnabled { return "8D on · \(player.reverbMode)" }
        return player.reverbMode == "Off" ? "Clean stereo" : player.reverbMode
    }

    private var playbackDetail: String {
        if let remaining = player.sleepRemaining { return "Sleep \(Int(remaining / 60))m" }
        if player.crossfadeSeconds > 0 { return "Crossfade \(Int(player.crossfadeSeconds))s" }
        return "Crossfade off"
    }

    private func studioDisclosureLabel(_ title: String, icon: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(EW27Design.cyan)
                .frame(width: 28, height: 28)
                .background(EW27Design.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(detail).font(.caption2).foregroundStyle(.white.opacity(0.42))
            }
        }
    }

    private var spatialControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Reverb", systemImage: "waveform.path")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("Reverb", selection: Binding(get: { player.reverbMode }, set: { player.setReverb(mode: $0) })) {
                    Text("Off").tag("Off")
                    Text("Room").tag("Room")
                    Text("Hall").tag("Hall")
                    Text("Cathedral").tag("Cathedral")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(.cyan)
            }
            if player.reverbMode != "Off" {
                HStack {
                    Text("Space")
                    Spacer()
                    Text(String(format: "%.0f%%", player.reverbWet))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.cyan)
                }
                Slider(value: Binding(get: { Double(player.reverbWet) }, set: { player.setReverbWet(Float($0)) }), in: 0...100)
                    .tint(.cyan)
            }
            Button { player.applySlowedReverbPreset() } label: {
                Label("Slowed + Reverb", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.cyan)
            Toggle(isOn: Binding(get: { player.eightDEnabled }, set: { player.setEightD(enabled: $0) })) {
                Label("8D Auto-pan", systemImage: "arrow.left.and.right.circle")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(.cyan)
            if player.eightDEnabled {
                HStack {
                    Text("Pan speed")
                    Spacer()
                    Text(String(format: "%.2f×", player.eightDSpeed))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { player.eightDSpeed }, set: { player.setEightDSpeed($0) }), in: 0.03...1.5)
                    .tint(.cyan)
            }
        }
    }

    private var playbackControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Sleep timer", systemImage: "moon.zzz")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("Sleep timer", selection: $sleepMinutes) {
                    Text("Off").tag(0)
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("60 min").tag(60)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(.cyan)
                .onChange(of: sleepMinutes) { _, value in player.startSleepTimer(minutes: value) }
            }
            if let remaining = player.sleepRemaining {
                Label(String(format: "Sleep in %.0f sec", remaining), systemImage: "timer")
                    .font(.caption)
                    .foregroundStyle(.cyan)
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("Crossfade", systemImage: "arrow.left.arrow.right")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(String(format: "%.0fs", player.crossfadeSeconds))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.cyan)
                }
                Slider(value: Binding(get: { player.crossfadeSeconds }, set: { player.setCrossfade($0) }), in: 0...12)
                    .tint(.cyan)
            }
            HStack(spacing: 8) {
                Button("A: mark") { player.setLoopA() }
                Button("B: mark") { player.setLoopB() }
                Button("Clear A-B") { player.clearABLoop() }
            }
            .buttonStyle(.bordered)
            .tint(.cyan)
        }
    }

    private var savedPresetsControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("Name this sound", text: $presetName)
                    .textFieldStyle(.roundedBorder)
                Button {
                    player.saveEffectPreset(named: presetName)
                    presetName = ""
                } label: {
                    Image(systemName: "plus")
                        .font(.headline.weight(.bold))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .accessibilityLabel("Save sound profile")
            }
            ForEach(player.customEffectPresets) { preset in
                HStack {
                    Button { player.applyEffectPreset(named: preset.name) } label: {
                        Label(preset.name, systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.medium))
                    }
                    Spacer()
                    Button("Delete", role: .destructive) { player.deleteEffectPreset(named: preset.name) }
                        .font(.caption.weight(.medium))
                }
            }
            if player.customEffectPresets.isEmpty {
                Text("Save a combination of EQ, speed and space for quick recall.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }
}
