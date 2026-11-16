import SwiftUI

struct SettingsSection: View {
    @AppStorage("ew27.haptics.enabled") private var hapticsEnabled = true
    @AppStorage("ew27.reset.speed.on.launch") private var resetSpeedOnLaunch = false
    @AppStorage("ew27.vinyl.enabled") private var vinylEnabled = false
    @AppStorage("ew27.spectrum.enabled") private var spectrumEnabled = true
    @AppStorage("ew27.lyrics.onlineLookup") private var onlineLyricsLookup = true
    @AppStorage("ew27.appearance") private var appearanceRawValue = EW27Appearance.system.rawValue
    @ObservedObject var player: AudioPlayer

    var body: some View {
        Section("Settings") {
            Picker("Appearance", selection: $appearanceRawValue) {
                ForEach(EW27Appearance.allCases) { appearance in
                    Label(appearance.title, systemImage: appearance.icon)
                        .tag(appearance.rawValue)
                }
            }
            Toggle("Haptics", isOn: $hapticsEnabled)
            Toggle("Reset speed to 1x on launch", isOn: $resetSpeedOnLaunch)
            Toggle("Online lyrics lookup", isOn: $onlineLyricsLookup)
                .onChange(of: onlineLyricsLookup) { _, enabled in player.lyricsStore.onlineLookupSettingChanged(enabled) }
            Text("Search sends the track title and artist to LRCLIB, NetEase, Apple Music, and Lyrics.ovh. LRCLIB also receives album and duration; Apple Music lyric lookup sends its song ID to paxsenix.org and zarz.moe.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Vinyl mode", isOn: $vinylEnabled)
            Picker("Brake on pause", selection: Binding(get: { player.brakeMode }, set: { player.setBrakeMode($0) })) {
                ForEach(BrakeController.Mode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
            Toggle("Spectrum analyzer", isOn: Binding(get: { spectrumEnabled }, set: { value in spectrumEnabled = value; player.setSpectrumEnabled(value) }))
            Toggle("Normalize loudness", isOn: Binding(get: { player.normalizeLoudness }, set: { player.setNormalizeLoudness($0) }))
        }
    }
}
