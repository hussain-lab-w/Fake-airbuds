import Foundation
import AVFoundation
import MediaPlayer
import UIKit

@MainActor
final class AudioPlayer: ObservableObject {
    static let shared = AudioPlayer()
    static let noRoute = "No output"

    enum Preset: String, CaseIterable, Identifiable, Codable {
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
    @Published private(set) var isPlaying = false {
        didSet {
            if isPlaying { startProgressTimer() }
            else { stopProgressTimer() }
        }
    }
    @Published private(set) var hasFinished = false
    @Published private(set) var routeName = noRoute
    @Published private(set) var playbackMessage: String?
    @Published private(set) var currentArtwork: UIImage?
    @Published private(set) var artworkTint: UIColor?
    @Published private(set) var audioQualityLabel = "Local audio"
    @Published var eqGains: [Float] = Array(repeating: 0, count: 10)
    @Published var eqEnabled = true
    @Published private(set) var activeEQProfileName: String?
    @Published var preamp: Float = 0
    @Published var selectedPreset: Preset = .flat
    @Published var shuffleEnabled = false
    @Published var keepPitch = false
    @Published var normalizeLoudness = false

    let clock = PlaybackClock()
    let speedState = SpeedState()
    let spectrumModel = SpectrumModel()

    var elapsed: TimeInterval {
        get { clock.elapsed }
        set { clock.elapsed = newValue }
    }

    var duration: TimeInterval {
        get { clock.duration }
        set { clock.duration = newValue }
    }

    func lyricPlaybackTime(at date: Date = Date()) -> TimeInterval {
        guard isPlaying, !isSeeking else {
            lyricsPlaybackClock.reset(to: elapsed, at: date)
            return elapsed
        }
        let reported: TimeInterval
        if engine.isRunning, playerNode.engine != nil,
           let renderTime = playerNode.lastRenderTime,
           let playerTime = playerNode.playerTime(forNodeTime: renderTime),
           playerTime.isSampleTimeValid,
           playerTime.sampleRate > 0 {
            let renderedTime = Double(playerTime.sampleTime) / playerTime.sampleRate
            if renderedTime.isFinite,
               renderedTime >= max(0, elapsed - 0.75),
               renderedTime <= min(duration, elapsed + 0.75) {
                reported = min(duration, max(0, renderedTime))
            } else {
                let elapsedSinceUpdate = max(0, date.timeIntervalSince(lastProgressDate))
                reported = min(duration, max(0, elapsed + elapsedSinceUpdate * Double(speed)))
            }
        } else {
            let elapsedSinceUpdate = max(0, date.timeIntervalSince(lastProgressDate))
            reported = min(duration, max(0, elapsed + elapsedSinceUpdate * Double(speed)))
        }
        return lyricsPlaybackClock.position(reported: reported, isPlaying: isPlaying, speed: Double(speed), at: date)
    }

    var speed: Float {
        get { speedState.displayed }
        set { speedState.displayed = newValue }
    }

    var spectrumBars: [Float] { spectrumModel.bars }

    let engine = AVAudioEngine()
    let playerNode = AVAudioPlayerNode()
    let fxMixer = AVAudioMixerNode()
    let panMixer = AVAudioMixerNode()
    let varispeed = AVAudioUnitVarispeed()
    let timePitch = AVAudioUnitTimePitch()
    let eq = AVAudioUnitEQ(numberOfBands: 16)
    let reverb = AVAudioUnitReverb()
    let limiter: AVAudioUnitEffect = {
        let description = AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        return AVAudioUnitEffect(audioComponentDescription: description)
    }()
    let spectrumAnalyzer = SpectrumAnalyzer()
    let waveformStore = WaveformStore()
    let lyricsStore = LyricsStore()
    private let lyricsPlaybackClock = MornyeLyricsPlaybackClock()
    let brakeController = BrakeController()

    private var audioFile: AVAudioFile?
    private var generation = 0
    private var trackOffset: TimeInterval = 0
    private var timer: Timer?
    private var rampTimer: Timer?
    private var routeObserver: NSObjectProtocol?
    private var configurationObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var wasPlayingBeforeInterruption = false
    private var isSeeking = false
    private var isHandlingConfiguration = false
    private var lastProgressDate = Date()
    private var rampStart: Float = 1
    private var rampTarget: Float = 1
    private var rampStartDate = Date()
    private var artworkCache: [UInt64: MPMediaItemArtwork] = [:]
    private var failedOpenCount = 0

    private let bandFrequencies: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    private let userDefaultsKey = "ew27.eq.settings.v2"
    private let globalSpeedDefaultsKey = "ew27.speed.global.v1"

    init() {
        configureEQ()
        if UserDefaults.standard.bool(forKey: "ew27.reset.speed.on.launch") {
            speed = 1
        } else if let storedSpeed = UserDefaults.standard.object(forKey: globalSpeedDefaultsKey) as? NSNumber {
            speed = max(0.25, min(4, storedSpeed.floatValue))
        } else {
            speed = 1
        }
        applyPlaybackRate()
        configureAudioSession()
        configureRemoteCommands()
        installObservers()
        updateRouteAndLoadSettings()
    }

    deinit {
        timer?.invalidate()
        rampTimer?.invalidate()
        for observer in [routeObserver, configurationObserver, interruptionObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var progress: Double { elapsed }

    func setBandGain(index: Int, gain: Float) {
        guard eqGains.indices.contains(index) else { return }
        eqGains[index] = max(-12, min(12, gain))
        applyEQSettings()
    }

    func setPreamp(_ value: Float) {
        preamp = max(-12, min(12, value))
        applyEQSettings()
    }

    func commitEQSettings() { saveSettingsForCurrentRoute() }

    func applyPreset(_ preset: Preset) {
        selectedPreset = preset
        switch preset {
        case .flat: eqGains = Array(repeating: 0, count: 10); preamp = 0
        case .bassBoost: eqGains = [5, 3, 0, -1, -2, 0, 0, 0, 0, 0]; preamp = -4
        case .vocal: eqGains = [-2, -1, 3, 4, 2, 1, 0, 0, -1, -2]; preamp = -2
        case .treble: eqGains = [-2, -1, 0, 3, 5, 4, 2, 1, 0, 0]; preamp = -4
        }
        applyEQSettings()
        saveSettingsForCurrentRoute()
    }

    func resetEQ() { applyPreset(.flat) }

    func setEQEnabled(_ enabled: Bool) {
        eqEnabled = enabled
        eq.bypass = !enabled
    }

    func clearEQProfile() {
        activeEQProfileName = nil
        applyPreset(.flat)
    }

    func applyEQProfile(_ profile: EQProfile) {
        activeEQProfileName = profile.name
        eqGains = Array(repeating: 0, count: 10)
        preamp = profile.preamp
        for filter in profile.filters.prefix(16) {
            if let index = bandFrequencies.firstIndex(where: { abs($0 - filter.frequency) < max(20, filter.frequency * 0.12) }) {
                eqGains[index] = filter.gain
                eq.bands[index].frequency = filter.frequency
                eq.bands[index].bandwidth = filter.bandwidth
                eq.bands[index].filterType = filter.kind == .lowShelf ? .lowShelf : (filter.kind == .highShelf ? .highShelf : .parametric)
            }
        }
        applyEQSettings()
        saveSettingsForCurrentRoute()
    }

    func importEQProfile(text: String, name: String) -> EQProfile? {
        guard let profile = AutoEQParser.parse(text, name: name) else { return nil }
        applyEQProfile(profile)
        return profile
    }

    func play(_ item: MPMediaItem, queue newQueue: [MPMediaItem]) {
        let playable = newQueue.filter { $0.assetURL != nil }
        guard !playable.isEmpty else { playbackMessage = "No playable audio files."; return }
        queue = playable
        currentIndex = playable.firstIndex(where: { $0.persistentID == item.persistentID }) ?? 0
        failedOpenCount = 0
        startCurrentTrack(at: 0, shouldPlay: true)
        persistSession()
    }

    func restoreSession() {
        guard let data = UserDefaults.standard.data(forKey: "ew27.session.v1"),
              let saved = try? JSONDecoder().decode(SessionSnapshot.self, from: data),
              let items = MPMediaQuery.songs().items else { return }
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.persistentID, $0) })
        let restoredQueue = saved.queueIDs.compactMap { byID[$0] }.filter { $0.assetURL != nil }
        guard !restoredQueue.isEmpty, let index = restoredQueue.firstIndex(where: { $0.persistentID == saved.currentID }) else { return }
        queue = restoredQueue
        currentIndex = index
        startCurrentTrack(at: saved.elapsed, shouldPlay: false)
    }

    func togglePlayPause() {
        if isPlaying { pause() }
        else if currentItem != nil && !hasFinished { playCurrentNode() }
        else if !queue.isEmpty { startCurrentTrack(at: 0, shouldPlay: true) }
    }

    func playCommand() {
        if hasFinished || currentItem == nil { startCurrentTrack(at: 0, shouldPlay: true) }
        else { playCurrentNode() }
    }

    func pause() {
        brakeController.rampDown { [weak self] in
            guard let self else { return }
            self.playerNode.pause()
            self.isPlaying = false
            self.lastProgressDate = Date()
            self.updateNowPlaying()
            self.persistSession()
        }
    }

    func nextTrack() {
        guard !queue.isEmpty else { return }
        currentIndex = nextIndex()
        failedOpenCount = 0
        startCurrentTrack(at: 0, shouldPlay: true)
        persistSession()
    }

    func addToQueue(_ item: MPMediaItem, playNext: Bool = false) {
        guard item.assetURL != nil, !queue.contains(where: { $0.persistentID == item.persistentID }) else { return }
        queue.insert(item, at: playNext ? min(currentIndex + 1, queue.count) : queue.count)
        persistSession()
    }

    func removeFromQueue(at offsets: IndexSet) {
        queue.remove(atOffsets: offsets)
        if let currentID = currentItem?.persistentID, let index = queue.firstIndex(where: { $0.persistentID == currentID }) { currentIndex = index }
        persistSession()
    }

    func clearUpcomingQueue() {
        guard !queue.isEmpty else { return }
        let end = min(queue.count, currentIndex + 1)
        queue = Array(queue.prefix(end))
        persistSession()
    }

    func moveQueue(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        if let currentID = currentItem?.persistentID, let index = queue.firstIndex(where: { $0.persistentID == currentID }) { currentIndex = index }
        persistSession()
    }

    func jumpToQueue(index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        startCurrentTrack(at: 0, shouldPlay: true)
    }

    func previousTrack() {
        guard !queue.isEmpty else { return }
        if elapsed > 3 { seek(to: 0) }
        else { currentIndex = previousIndex(); failedOpenCount = 0; startCurrentTrack(at: 0, shouldPlay: true) }
    }

    func seek(to time: TimeInterval) {
        guard currentItem != nil, duration > 0, !isSeeking else { return }
        let target = max(0, min(duration, time))
        isSeeking = true
        generation &+= 1
        let token = generation
        let resume = isPlaying
        if playerNode.engine != nil { playerNode.stop() }
        trackOffset = target
        elapsed = target
        scheduleCurrentSegment(token: token, shouldPlay: resume)
        updateNowPlaying()
        isSeeking = false
    }

    func setSpeed(_ value: Float) {
        let target = max(0.25, min(4, value))
        rampTimer?.invalidate()
        rampStart = speed
        rampTarget = target
        rampStartDate = Date()
        rampTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                let fraction = min(1, Date().timeIntervalSince(self.rampStartDate) / 0.6)
                let eased = Float(fraction * fraction * (3 - 2 * fraction))
                self.speed = self.rampStart + (self.rampTarget - self.rampStart) * eased
                self.applyPlaybackRate()
                if fraction >= 1 {
                    timer.invalidate()
                    self.rampTimer = nil
                    UserDefaults.standard.set(Double(self.speed), forKey: self.globalSpeedDefaultsKey)
                    self.updateNowPlaying()
                }
            }
        }
    }

    func setSpeedWhileDragging(_ value: Float) {
        let target = max(0.25, min(4, value))
        rampTimer?.invalidate()
        speed = speed + (target - speed) * 0.35
        applyPlaybackRate()
    }

    private struct SessionSnapshot: Codable {
        var currentID: UInt64
        var elapsed: TimeInterval
        var queueIDs: [UInt64]
    }

    private func persistSession() {
        guard let currentID = currentItem?.persistentID, !queue.isEmpty else { return }
        let snapshot = SessionSnapshot(currentID: currentID, elapsed: elapsed, queueIDs: queue.map(\.persistentID))
        if let data = try? JSONEncoder().encode(snapshot) { UserDefaults.standard.set(data, forKey: "ew27.session.v1") }
    }

    func setSpectrumEnabled(_ enabled: Bool) { spectrumAnalyzer.setEnabled(enabled) }

    var brakeMode: BrakeController.Mode { brakeController.mode }

    func setBrakeMode(_ mode: BrakeController.Mode) { brakeController.mode = mode }

    func setNormalizeLoudness(_ enabled: Bool) {
        normalizeLoudness = enabled
        guard enabled, let item = currentItem, let url = item.assetURL else { applyLoudnessGain(0); return }
        LoudnessNormalizer.gain(for: url, persistentID: item.persistentID) { [weak self] gain in self?.applyLoudnessGain(gain) }
    }

    private func applyLoudnessGain(_ gain: Float) {
        let unit = limiter.audioUnit
        _ = AudioUnitSetParameter(unit, 0, kAudioUnitScope_Global, 0, gain, 0)
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowBluetoothA2DP])
            try session.setActive(true)
        } catch { }
    }

    private func configureEQ() {
        for (index, frequency) in bandFrequencies.enumerated() {
            let band = eq.bands[index]
            band.frequency = frequency
            band.bandwidth = 1
            band.gain = 0
            band.bypass = false
            band.filterType = index == 0 ? .lowShelf : (index == bandFrequencies.count - 1 ? .highShelf : .parametric)
        }
        for index in 10..<eq.bands.count { eq.bands[index].bypass = true }
        limiter.auAudioUnit.shouldBypassEffect = false
        timePitch.pitch = 0
        reverb.wetDryMix = 0
    }

    private func attachNodesIfNeeded() {
        for node in [playerNode as AVAudioNode, fxMixer, varispeed, timePitch, eq, reverb, limiter, panMixer] where !engine.attachedNodes.contains(node) { engine.attach(node) }
    }

    private func rebuildGraph(format: AVAudioFormat) {
        engine.stop()
        spectrumAnalyzer.remove(from: engine.mainMixerNode)
        for node in [playerNode as AVAudioNode, fxMixer, varispeed, timePitch, eq, reverb, limiter, panMixer] where engine.attachedNodes.contains(node) { engine.disconnectNodeOutput(node) }
        attachNodesIfNeeded()
        engine.connect(playerNode, to: fxMixer, format: format)
        engine.connect(fxMixer, to: varispeed, format: format)
        engine.connect(varispeed, to: timePitch, format: format)
        engine.connect(timePitch, to: eq, format: format)
        engine.connect(eq, to: reverb, format: format)
        engine.connect(reverb, to: limiter, format: format)
        engine.connect(limiter, to: panMixer, format: format)
        engine.connect(panMixer, to: engine.mainMixerNode, format: format)
        spectrumAnalyzer.install(on: engine.mainMixerNode, model: spectrumModel)
        applyEQSettings()
        applyPlaybackRate()
    }

    private func startCurrentTrack(at startTime: TimeInterval, shouldPlay: Bool) {
        guard queue.indices.contains(currentIndex) else { return }
        let item = queue[currentIndex]
        guard let url = item.assetURL else { skipUnavailableTrack(); return }
        generation &+= 1
        let token = generation
        if playerNode.engine != nil { playerNode.stop() }
        fxMixer.outputVolume = crossfadeSeconds > 0 ? 0 : 1
        elapsed = 0
        hasFinished = false
        do {
            if engine.attachedNodes.contains(playerNode), engine.isRunning == false { configureAudioSession() }
            let file = try AVAudioFile(forReading: url)
            audioFile = file
            currentItem = item
            currentArtwork = item.artwork?.image(at: CGSize(width: 240, height: 240))
            artworkTint = ArtworkCache.shared.averageColor(for: currentArtwork)
            waveformStore.load(url: url, persistentID: item.persistentID)
            if normalizeLoudness {
                LoudnessNormalizer.gain(for: url, persistentID: item.persistentID) { [weak self] gain in self?.applyLoudnessGain(gain) }
            }
            duration = TimeInterval(file.length) / file.processingFormat.sampleRate
            audioQualityLabel = Self.qualityLabel(for: file.processingFormat)
            lyricsStore.load(for: item, duration: duration)
            trackOffset = max(0, min(duration, startTime))
            rebuildGraph(format: file.processingFormat)
            failedOpenCount = 0
            playbackMessage = nil
            scheduleCurrentSegment(token: token, shouldPlay: shouldPlay)
            updateNowPlaying()
        } catch {
            playbackMessage = "Couldn't open this track; skipping."
            isPlaying = false
            skipUnavailableTrack()
        }
    }

    private func scheduleCurrentSegment(token: Int, shouldPlay: Bool) {
        guard let file = audioFile, file.processingFormat.sampleRate > 0 else { return }
        let sampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(trackOffset * sampleRate)
        let remaining = max(0, file.length - startFrame)
        guard remaining > 0 else { finishTrack(token: token); return }
        playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: AVAudioFrameCount(remaining), at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.finishTrack(token: token)
            }
        }
        if !engine.isRunning { do { try engine.start() } catch { playbackMessage = "Couldn't start the audio engine."; isPlaying = false; return } }
        elapsed = trackOffset
        lastProgressDate = Date()
        if shouldPlay { playCurrentNode() } else { isPlaying = false; updateNowPlaying() }
    }

    private func playCurrentNode() {
        guard currentItem != nil else { return }
        do {
            if !engine.isRunning { try engine.start() }
            brakeController.rampUp()
            playerNode.play()
            isPlaying = true
            hasFinished = false
            lastProgressDate = Date()
            updateNowPlaying()
        } catch { isPlaying = false }
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

    private func skipUnavailableTrack() {
        guard !queue.isEmpty else { isPlaying = false; hasFinished = true; return }
        failedOpenCount += 1
        guard failedOpenCount < queue.count else {
            playbackMessage = "No playable track found."
            isPlaying = false
            hasFinished = true
            return
        }
        currentIndex = nextIndex()
        startCurrentTrack(at: 0, shouldPlay: true)
    }

    private func nextIndex() -> Int {
        guard !queue.isEmpty else { return 0 }
        if shuffleEnabled && queue.count > 1 {
            var value = Int.random(in: 0..<queue.count)
            while value == currentIndex { value = Int.random(in: 0..<queue.count) }
            return value
        }
        return (currentIndex + 1) % queue.count
    }

    private func previousIndex() -> Int { queue.isEmpty ? 0 : (currentIndex - 1 + queue.count) % queue.count }

    private func startProgressTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateProgress() }
        }
    }

    private func stopProgressTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateProgress() {
        guard isPlaying, !isSeeking else { return }
        let now = Date()
        elapsed = min(duration, elapsed + now.timeIntervalSince(lastProgressDate) * Double(speed))
        lastProgressDate = now
        if elapsed >= duration { elapsed = duration }
        let fadeDuration = min(crossfadeSeconds, duration / 2)
        guard engine.isRunning, fxMixer.engine != nil else { return }
        if fadeDuration > 0 {
            let fadeIn = min(1, max(0, elapsed / fadeDuration))
            let fadeOut = min(1, max(0, (duration - elapsed) / fadeDuration))
            fxMixer.outputVolume = Float(min(fadeIn, fadeOut))
        } else {
            fxMixer.outputVolume = 1
        }
    }

    private func applyPlaybackRate() {
        let rate = max(0.25, min(4, speed * brakeController.factor))
        if keepPitch { varispeed.rate = 1; timePitch.rate = rate }
        else { varispeed.rate = rate; timePitch.rate = 1 }
    }

    private func updateNowPlaying() {
        guard let item = currentItem else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title ?? "Untitled",
            MPMediaItemPropertyArtist: item.artist ?? "",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(speed) : 0.0,
            MPMediaItemPropertyPlaybackDuration: duration
        ]
        if let artwork = artworkCache[item.persistentID] { info[MPMediaItemPropertyArtwork] = artwork }
        else if let image = item.artwork?.image(at: CGSize(width: 600, height: 600)) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            artworkCache[item.persistentID] = artwork
            info[MPMediaItemPropertyArtwork] = artwork
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
        center.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.togglePlayPause() }; return .success }
        center.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.playCommand() }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.nextTrack() }; return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previousTrack() }; return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func installObservers() {
        let center = NotificationCenter.default
        routeObserver = center.addObserver(forName: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] notification in Task { @MainActor in self?.handleRouteChange(notification) } }
        configurationObserver = center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in Task { @MainActor in self?.handleEngineConfigurationChange() } }
        interruptionObserver = center.addObserver(forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] notification in Task { @MainActor in self?.handleInterruption(notification) } }
    }

    private func handleRouteChange(_ notification: Notification) {
        let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        let reason = raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
        updateRouteAndLoadSettings()
        if reason == .oldDeviceUnavailable { pause() }
    }

    private func handleEngineConfigurationChange() {
        guard !isHandlingConfiguration, currentItem != nil else { return }
        isHandlingConfiguration = true
        let resume = isPlaying
        restartCurrentTrackPreservingPosition(shouldPlay: resume)
        DispatchQueue.main.async { [weak self] in self?.isHandlingConfiguration = false }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began: wasPlayingBeforeInterruption = isPlaying; pause()
        case .ended:
            let value = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            if wasPlayingBeforeInterruption && AVAudioSession.InterruptionOptions(rawValue: value).contains(.shouldResume) { playCurrentNode() }
        @unknown default: break
        }
    }

    private func restartCurrentTrackPreservingPosition(shouldPlay: Bool) {
        guard currentItem != nil else { return }
        startCurrentTrack(at: elapsed, shouldPlay: shouldPlay)
    }

    private func updateRouteAndLoadSettings() {
        routeName = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? Self.noRoute
        loadSettingsForCurrentRoute()
    }

    private func routeKey() -> String {
        let name = routeName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "unknown" : name
    }

    private func storedSettings() -> [String: EQSettings] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey), let values = try? JSONDecoder().decode([String: EQSettings].self, from: data) else { return [:] }
        return values
    }

    private func loadSettingsForCurrentRoute() {
        if let settings = storedSettings()[routeKey()] {
            eqGains = settings.gains.count == 10 ? settings.gains : migrateGains(settings.gains)
            preamp = settings.globalGain
            selectedPreset = settings.preset
        } else { eqGains = Array(repeating: 0, count: 10); preamp = 0; selectedPreset = .flat }
        applyEQSettings()
    }

    private func saveSettingsForCurrentRoute() {
        var values = storedSettings()
        values[routeKey()] = EQSettings(gains: eqGains, globalGain: preamp, preset: selectedPreset)
        if let data = try? JSONEncoder().encode(values) { UserDefaults.standard.set(data, forKey: userDefaultsKey) }
    }

    private func applyEQSettings() {
        for index in eq.bands.indices where index < eqGains.count { eq.bands[index].gain = eqGains[index]; eq.bands[index].bypass = false }
        for index in 10..<eq.bands.count { eq.bands[index].bypass = true }
        eq.globalGain = preamp
        eq.bypass = !eqEnabled
    }

    private static func qualityLabel(for format: AVAudioFormat) -> String {
        let rate = Int(format.sampleRate.rounded())
        let rateText: String
        switch rate {
        case 88_000...: rateText = "88.2kHz+"
        case 48_000...: rateText = "48kHz"
        default: rateText = "44.1kHz"
        }
        let channels = format.channelCount == 1 ? "Mono" : "Stereo"
        return "\(rateText) · \(channels)"
    }

    private func migrateGains(_ old: [Float]) -> [Float] {
        guard old.count == 5 else { return Array(repeating: 0, count: 10) }
        return [old[0], old[0], old[1], old[1], old[2], old[2], old[3], old[3], old[4], old[4]]
    }
}
