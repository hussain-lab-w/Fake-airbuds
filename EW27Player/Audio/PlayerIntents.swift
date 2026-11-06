import AppIntents
import Foundation

@MainActor
final class AudioPlayerIntentBridge {
    static let shared = AudioPlayerIntentBridge()
    weak var player: AudioPlayer?
    private init() {}
    func register(_ player: AudioPlayer) { self.player = player }
}

struct SetSpeedIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Player Speed"
    static var description = IntentDescription("Set EW27 Player playback speed.")
    @Parameter(title: "Speed", description: "Playback speed from 0.25× to 4×") var speed: Double
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run { AudioPlayerIntentBridge.shared.player?.setSpeed(Float(speed)) }
        return .result(dialog: "Playback speed updated.")
    }
}

struct ToggleEightDIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle 8D Audio"
    static var description = IntentDescription("Turn EW27 Player 8D auto-pan on or off.")
    @Parameter(title: "Enabled") var enabled: Bool
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run { AudioPlayerIntentBridge.shared.player?.setEightD(enabled: enabled) }
        return .result(dialog: enabled ? "8D audio enabled." : "8D audio disabled.")
    }
}

struct ApplyEffectPresetIntent: AppIntent {
    static var title: LocalizedStringResource = "Apply Audio Preset"
    static var description = IntentDescription("Apply a saved EW27 Player effects preset.")
    @Parameter(title: "Preset name") var name: String
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run { AudioPlayerIntentBridge.shared.player?.applyEffectPreset(named: name) }
        return .result(dialog: "Preset applied.")
    }
}

struct PlayerPlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Play or Pause EW27 Player"
    static var description = IntentDescription("Toggle playback in EW27 Player.")
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run { AudioPlayerIntentBridge.shared.player?.togglePlayPause() }
        return .result(dialog: "Playback toggled.")
    }
}

struct PlayerNextTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Track in EW27 Player"
    static var description = IntentDescription("Skip to the next track in EW27 Player.")
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run { AudioPlayerIntentBridge.shared.player?.nextTrack() }
        return .result(dialog: "Skipped to the next track.")
    }
}

struct EW27PlayerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlayerPlayPauseIntent(), phrases: ["Play or pause with \(.applicationName)", "Toggle playback with \(.applicationName)"], shortTitle: "Play/Pause", systemImageName: "playpause.fill")
        AppShortcut(intent: PlayerNextTrackIntent(), phrases: ["Next track with \(.applicationName)"], shortTitle: "Next Track", systemImageName: "forward.fill")
        AppShortcut(intent: SetSpeedIntent(), phrases: ["Set speed with \(.applicationName)"], shortTitle: "Set Speed", systemImageName: "speedometer")
        AppShortcut(intent: ToggleEightDIntent(), phrases: ["Toggle 8D with \(.applicationName)"], shortTitle: "Toggle 8D", systemImageName: "hifispeaker.2.fill")
        AppShortcut(intent: ApplyEffectPresetIntent(), phrases: ["Apply preset with \(.applicationName)"], shortTitle: "Apply Preset", systemImageName: "slider.horizontal.3")
    }
}
