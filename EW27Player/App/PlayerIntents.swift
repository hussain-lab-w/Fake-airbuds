import AppIntents

struct SetSpeedIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Playback Speed"
    static var openAppWhenRun = false
    @Parameter(title: "Speed") var speed: Double
    func perform() async throws -> some IntentResult { await MainActor.run { AudioPlayer.shared.setSpeed(Float(speed)) }; return .result() }
}

struct ToggleEQIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle EQ"
    static var openAppWhenRun = false
    func perform() async throws -> some IntentResult { await MainActor.run { AudioPlayer.shared.setEQEnabled(!AudioPlayer.shared.eqEnabled) }; return .result() }
}

struct ApplyPresetIntent: AppIntent {
    static var title: LocalizedStringResource = "Apply EQ Preset"
    static var openAppWhenRun = false
    @Parameter(title: "Preset") var preset: String
    func perform() async throws -> some IntentResult {
        await MainActor.run { if let value = AudioPlayer.Preset(rawValue: preset) { AudioPlayer.shared.applyPreset(value) } }
        return .result()
    }
}

struct PlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Play or Pause"
    static var openAppWhenRun = false
    func perform() async throws -> some IntentResult { await MainActor.run { AudioPlayer.shared.togglePlayPause() }; return .result() }
}

struct NextTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Track"
    static var openAppWhenRun = false
    func perform() async throws -> some IntentResult { await MainActor.run { AudioPlayer.shared.nextTrack() }; return .result() }
}

struct PreviousTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous Track"
    static var openAppWhenRun = false
    func perform() async throws -> some IntentResult { await MainActor.run { AudioPlayer.shared.previousTrack() }; return .result() }
}

struct EW27PlayerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        [
            AppShortcut(intent: PlayPauseIntent(), phrases: ["Play or pause in \\(.applicationName)"], shortTitle: "Play/Pause", systemImageName: "playpause"),
            AppShortcut(intent: NextTrackIntent(), phrases: ["Next track in \\(.applicationName)"], shortTitle: "Next", systemImageName: "forward.fill"),
            AppShortcut(intent: ToggleEQIntent(), phrases: ["Toggle EQ in \\(.applicationName)"], shortTitle: "Toggle EQ", systemImageName: "slider.horizontal.3")
        ]
    }
}
