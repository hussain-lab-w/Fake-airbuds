import Foundation
import AVFoundation
import MediaPlayer

@MainActor
final class AudioPlayer: ObservableObject {
    enum Preset: String, CaseIterable, Identifiable {
        case flat = "Flat"
        case bassBoost = "Bass Boost"
        case vocal = "Vocal"
        case treble = "Treble"

        var id: String { rawValue }
    }

    private struct EQSettings: Codable {
        var gains: [Float]
        var globalGain: Float
        var preset: Preset
    }

    @Published private(set) var currentItem: MPMediaItem?
    @Published private(set) var queue: [MPMediaItem] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var hasFinished = false
    @Published private(set) var routeName = "لا يوجد مسار"
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var eqGains: [Float] = Array(repeating: 0, count: 5)
    @Published var preamp: Float = 0
    @Published var selectedPreset: Preset = .flat
    @Published var shuffleEnabled = false

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 5)
    private lazy var limiter: AVAudioUnitEffect = {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return AVAudioUnitEffect(audioComponentDescription: description)
    }()

    private var audioFile: AVAudioFile?
    private var generation = 0
    private var trackOffset: TimeInterval = 0
    private var timer: Timer?
    private var routeObserver: NSObjectProtocol?
    private var configurationObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var wasPlayingBeforeInterruption = false
    private var wasPlayingBeforeRouteChange = false
    private var isSeeking = false

    private let bandFrequencies: [Float] = [60, 250, 1000, 4000, 12000]
    private let userDefaultsKey = "ew27.eq.settings.v2"

    init() {
        configureEQ()
        configureAudioSession()
        configureRemoteCommands()
        installObservers()
        updateRouteAndLoadSettings()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateProgress() }
        }
    }

    deinit {
        timer?.invalidate()
        for observer in [routeObserver, configurationObserver, interruptionObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var progress: Double {
        get { elapsed }
        set { seek(to: newValue) }
    }

    func setBandGain(index: Int, gain: Float) {
        guard eqGains.indices.contains(index) else { return }
        eqGains[index] = max(-12, min(12, gain))
        applyEQSettings()
        saveSettingsForCurrentRoute()
    }

    func setPreamp(_ value: Float) {
        preamp = max(-12, min(12, value))
        applyEQSettings()
        saveSettingsForCurrentRoute()
    }

    func applyPreset(_ preset: Preset) {
        selectedPreset = preset
        switch preset {
        case .flat:
            eqGains = [0, 0, 0, 0, 0]
            preamp = 0
        case .bassBoost:
            eqGains = [5, 3, 0, -1, -2]
            preamp = -4
        case .vocal:
            eqGains = [-2, -1, 3, 4, 2]
            preamp = -2
        case .treble:
            eqGains = [-2, -1, 0, 3, 5]
            preamp = -4
        }
        applyEQSettings()
        saveSettingsForCurrentRoute()
    }

    func resetEQ() {
        applyPreset(.flat)
    }

    func play(_ item: MPMediaItem, queue newQueue: [MPMediaItem]) {
        guard item.assetURL != nil else { return }
        let playable = newQueue.filter { $0.assetURL != nil }
        guard !playable.isEmpty else { return }
        queue = playable
        currentIndex = playable.firstIndex(where: { $0.persistentID == item.persistentID }) ?? 0
        startCurrentTrack(at: 0, shouldPlay: true)
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else if currentItem != nil && !hasFinished {
            playCurrentNode()
        } else if !queue.isEmpty {
            startCurrentTrack(at: 0, shouldPlay: true)
        }
    }

    func playCommand() {
        if hasFinished || currentItem == nil { startCurrentTrack(at: 0, shouldPlay: true) }
        else { playCurrentNode() }
    }

    func pause() {
        playerNode.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func nextTrack() {
        guard !queue.isEmpty else { return }
        currentIndex = nextIndex()
        startCurrentTrack(at: 0, shouldPlay: true)
    }

    func previousTrack() {
        guard !queue.isEmpty else { return }
        if elapsed > 3 {
            startCurrentTrack(at: 0, shouldPlay: isPlaying)
        } else {
            currentIndex = previousIndex()
            startCurrentTrack(at: 0, shouldPlay: true)
        }
    }

    func seek(to time: TimeInterval) {
        guard currentItem != nil, duration > 0, !isSeeking else { return }
        let target = max(0, min(duration, time))
        isSeeking = true
        let shouldPlay = isPlaying
        startCurrentTrack(at: target, shouldPlay: shouldPlay)
        isSeeking = false
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .music, options: [.allowBluetoothA2DP])
            try session.setActive(true)
        } catch { }
    }

    private func configureEQ() {
        for (index, frequency) in bandFrequencies.enumerated() {
            let band = eq.bands[index]
            band.frequency = frequency
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false
            if index == 0 {
                band.filterType = .lowShelf
            } else if index == bandFrequencies.count - 1 {
                band.filterType = .highShelf
            } else {
                band.filterType = .parametric
            }
        }
        limiter.auAudioUnit.shouldBypassEffect = false
    }

    private func attachNodesIfNeeded() {
        if !engine.attachedNodes.contains(playerNode) { engine.attach(playerNode) }
        if !engine.attachedNodes.contains(eq) { engine.attach(eq) }
        if !engine.attachedNodes.contains(limiter) { engine.attach(limiter) }
    }

    private func rebuildGraph(format: AVAudioFormat) {
        engine.stop()
        engine.disconnectNodeOutput(playerNode)
        engine.disconnectNodeOutput(eq)
        engine.disconnectNodeOutput(limiter)
        attachNodesIfNeeded()
        engine.connect(playerNode, to: eq, format: format)
        engine.connect(eq, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)
        applyEQSettings()
    }

    private func startCurrentTrack(at startTime: TimeInterval, shouldPlay: Bool) {
        guard queue.indices.contains(currentIndex), let url = queue[currentIndex].assetURL else { return }
        generation &+= 1
        let token = generation
        playerNode.stop()
        elapsed = 0
        hasFinished = false

        do {
            configureAudioSession()
            let file = try AVAudioFile(forReading: url)
            audioFile = file
            duration = TimeInterval(file.length) / file.processingFormat.sampleRate
            trackOffset = max(0, min(duration, startTime))
            rebuildGraph(format: file.processingFormat)
            let sampleRate = file.processingFormat.sampleRate
            let startFrame = AVAudioFramePosition(trackOffset * sampleRate)
            let remainingFrames = max(0, file.length - startFrame)
            guard remainingFrames > 0 else { finishTrack(token: token); return }
            playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: AVAudioFrameCount(remainingFrames), at: nil) { [weak self] in
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    self.finishTrack(token: token)
                }
            }
            if !engine.isRunning { try engine.start() }
            currentItem = queue[currentIndex]
            elapsed = trackOffset
            updateNowPlaying()
            if shouldPlay { playCurrentNode() } else { isPlaying = false }
        } catch {
            isPlaying = false
            hasFinished = true
        }
    }

    private func playCurrentNode() {
        guard currentItem != nil else { return }
        do {
            if !engine.isRunning { try engine.start() }
            playerNode.play()
            isPlaying = true
            hasFinished = false
            updateNowPlaying()
        } catch {
            isPlaying = false
        }
    }

    private func finishTrack(token: Int) {
        guard generation == token else { return }
        isPlaying = false
        hasFinished = true
        elapsed = duration
        updateNowPlaying()
        guard !queue.isEmpty else { return }
        currentIndex = nextIndex()
        startCurrentTrack(at: 0, shouldPlay: true)
    }

    private func nextIndex() -> Int {
        guard !queue.isEmpty else { return 0 }
        if shuffleEnabled, queue.count > 1 {
            var value = Int.random(in: 0..<queue.count)
            while value == currentIndex { value = Int.random(in: 0..<queue.count) }
            return value
        }
        return (currentIndex + 1) % queue.count
    }

    private func previousIndex() -> Int {
        guard !queue.isEmpty else { return 0 }
        return (currentIndex - 1 + queue.count) % queue.count
    }

    private func updateProgress() {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNode: playerNode),
              playerTime.sampleRate > 0,
              !isSeeking else { return }
        let nodeElapsed = Double(playerTime.sampleTime) / playerTime.sampleRate
        elapsed = max(0, min(duration, trackOffset + nodeElapsed))
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        guard let item = currentItem else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title ?? "بدون عنوان",
            MPMediaItemPropertyArtist: item.artist ?? "",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPMediaItemPropertyPlaybackDuration: duration
        ]
        if let artwork = item.artwork?.image(at: CGSize(width: 600, height: 600)) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.isEnabled = true
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true

        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playCommand() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.nextTrack() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previousTrack() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func installObservers() {
        let center = NotificationCenter.default
        routeObserver = center.addObserver(forName: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] notification in
            Task { @MainActor in self?.handleRouteChange(notification) }
        }
        configurationObserver = center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleEngineConfigurationChange() }
        }
        interruptionObserver = center.addObserver(forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] notification in
            Task { @MainActor in self?.handleInterruption(notification) }
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        let reason = reasonValue.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
        wasPlayingBeforeRouteChange = isPlaying
        updateRouteAndLoadSettings()
        if reason == .oldDeviceUnavailable {
            pause()
            restartCurrentTrackPreservingPosition(shouldPlay: false)
        } else if wasPlayingBeforeRouteChange {
            restartCurrentTrackPreservingPosition(shouldPlay: true)
        }
    }

    private func handleEngineConfigurationChange() {
        guard currentItem != nil else { return }
        restartCurrentTrackPreservingPosition(shouldPlay: isPlaying)
    }

    private func handleInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            pause()
        case .ended:
            let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            try? AVAudioSession.sharedInstance().setActive(true)
            if wasPlayingBeforeInterruption && options.contains(.shouldResume) {
                restartCurrentTrackPreservingPosition(shouldPlay: true)
            }
        @unknown default:
            break
        }
    }

    private func restartCurrentTrackPreservingPosition(shouldPlay: Bool) {
        guard currentItem != nil else { return }
        startCurrentTrack(at: elapsed, shouldPlay: shouldPlay)
    }

    private func updateRouteAndLoadSettings() {
        routeName = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "لا يوجد مسار"
        loadSettingsForCurrentRoute()
    }

    private func routeKey() -> String {
        let name = routeName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "unknown" : name
    }

    private func storedSettings() -> [String: EQSettings] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let values = try? JSONDecoder().decode([String: EQSettings].self, from: data) else { return [:] }
        return values
    }

    private func loadSettingsForCurrentRoute() {
        if let settings = storedSettings()[routeKey()] {
            eqGains = settings.gains.count == 5 ? settings.gains : Array(repeating: 0, count: 5)
            preamp = settings.globalGain
            selectedPreset = settings.preset
        } else {
            eqGains = [0, 0, 0, 0, 0]
            preamp = 0
            selectedPreset = .flat
        }
        applyEQSettings()
    }

    private func saveSettingsForCurrentRoute() {
        var values = storedSettings()
        values[routeKey()] = EQSettings(gains: eqGains, globalGain: preamp, preset: selectedPreset)
        if let data = try? JSONEncoder().encode(values) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    private func applyEQSettings() {
        for index in eq.bands.indices where index < eqGains.count {
            eq.bands[index].gain = eqGains[index]
            eq.bands[index].bypass = false
        }
        eq.globalGain = preamp
    }
}
