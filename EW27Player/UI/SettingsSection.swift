import SwiftUI

struct SettingsSection: View {
    @AppStorage("ew27.haptics.enabled") private var hapticsEnabled = true
    @AppStorage("ew27.reset.speed.on.launch") private var resetSpeedOnLaunch = false
    @AppStorage("ew27.vinyl.enabled") private var vinylEnabled = false
    @AppStorage("ew27.spectrum.enabled") private var spectrumEnabled = true
    @ObservedObject var player: AudioPlayer

    var body: some View {
        Section("Settings") {
            Toggle("Haptics", isOn: $hapticsEnabled)
            Toggle("Reset speed to 1x on launch", isOn: $resetSpeedOnLaunch)
            Toggle("Vinyl mode", isOn: $vinylEnabled)
            Picker("Brake on pause", selection: Binding(get: { player.brakeMode }, set: { player.setBrakeMode($0) })) {
                ForEach(BrakeController.Mode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
            Toggle("Spectrum analyzer", isOn: Binding(get: { spectrumEnabled }, set: { value in spectrumEnabled = value; player.setSpectrumEnabled(value) }))
            Toggle("Normalize loudness", isOn: Binding(get: { player.normalizeLoudness }, set: { player.setNormalizeLoudness($0) }))
        }
    }
}
