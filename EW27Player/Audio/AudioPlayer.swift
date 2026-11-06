import Foundation
import AVFoundation
import MediaPlayer

@MainActor
final class AudioPlayer: ObservableObject {
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
    @Published private(set) var isPlaying = false
    @Published private(set) var hasFinished = false
    @Published private(set) var routeName = "لا يوجد مسار"
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var playbackMessage: String?
    @Published var eqGains: [Float] = Array(repeating: 0, count: 5)
    @Published var preamp: Float = 0
    @Published var selectedPreset: Preset = .flat
    @Published var shuffleEnabled = false
    @Published private(set) var speed: Float = 1
    @Published var keepPitch = false

    let engine = AVAudioEngine()
    let playerNode = AVAudioPlayerNode()
    let fxMixer = AVAudioMixerNode()
    let varispeed = AVAudioUnitVarispeed()
    let timePitch = AVAudioUnitTimePitch()
    let eq = AVAudioUnitEQ(numberOfBands: 5)
    let reverb = AVAudioUnitReverb()
    let limiter: AVAudioUnitEffect = {
        let description = AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        return AVAudioUnitEffect(audioComponentDescription: description)
    }()

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

    private let bandFrequencies: [Float] = [60, 250, 1000, 4000, 12000]
    private let userDefaultsKey = "ew27.eq.settings.v2"
    private let speedDefaultsKey = "ew27.speed.byTrack.v1"

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
        case .flat: eqGains = [0, 0, 0, 0, 0]; preamp = 0
        case .bassBoost: eqGains = [5, 3, 0, -1, -2]; preamp = -4
        case .vocal: eqGains = [-2, -1, 3, 4, 2]; preamp = -2
        case .treble: eqGains = [-2, -1, 0, 3, 5]; preamp = -4
        }
        applyEQSettings()
        saveSettingsForCurrentRoute()
    }

    func resetEQ() { applyPreset(.flat) }

    func play(_ item: MPMediaItem, queue newQueue: [MPMediaItem]) {
        let playable = newQueue.filter { $0.assetURL != nil }
        guard !playable.isEmpty else { playbackMessage = "لا توجد ملفات صوتية قابلة للتشغيل."; return }
        queue = playable
        currentIndex = playable.firstIndex(where: { $0.persistentID == item.persistentID }) ?? 0
        failedOpenCount = 0
        startCurrentTrack(at: 0, shouldPlay: true)
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
        playerNode.pause()
        isPlaying = false
        lastProgressDate = Date()
        updateNowPlaying()
    }

    func nextTrack() {
        guard !queue.isEmpty else { return }
        currentIndex = nextIndex()
        failedOpenCount = 0
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
                self.saveSpeedForCurrentTrack()
                if fraction >= 1 { timer.invalidate(); self.rampTimer = nil; self.updateNowPlaying() }
            }
        }
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
        limiter.auAudioUnit.shouldBypassEffect = false
        timePitch.pitch = 0
        reverb.wetDryMix = 0
    }

    private func attachNodesIfNeeded() {
        for node in [playerNode as AVAudioNode, fxMixer, varispeed, timePitch, eq, reverb, limiter] where !engine.attachedNodes.contains(node) { engine.attach(node) }
    }

    private func rebuildGraph(format: AVAudioFormat) {
        engine.stop()
        for node in [playerNode as AVAudioNode, fxMixer, varispeed, timePitch, eq, reverb, limiter] where engine.attachedNodes.contains(node) { engine.disconnectNodeOutput(node) }
        attachNodesIfNeeded()
        engine.connect(playerNode, to: fxMixer, format: format)
        engine.connect(fxMixer, to: varispeed, format: format)
        engine.connect(varispeed, to: timePitch, format: format)
        engine.connect(timePitch, to: eq, format: format)
        engine.connect(eq, to: reverb, format: format)
        engine.connect(reverb, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)
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
            duration = TimeInterval(file.length) / file.processingFormat.sampleRate
            trackOffset = max(0, min(duration, startTime))
            speed = loadSpeed(for: item)
            rebuildGraph(format: file.processingFormat)
            failedOpenCount = 0
            playbackMessage = nil
            scheduleCurrentSegment(token: token, shouldPlay: shouldPlay)
            updateNowPlaying()
        } catch {
            playbackMessage = "تعذر فتح الأغنية؛ جارٍ تخطيها."
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
        if !engine.isRunning { do { try engine.start() } catch { playbackMessage = "تعذر بدء محرك الصوت."; isPlaying = false; return } }
        elapsed = trackOffset
        lastProgressDate = Date()
        if shouldPlay { playCurrentNode() } else { isPlaying = false; updateNowPlaying() }
    }

    private func playCurrentNode() {
        guard currentItem != nil else { return }
        do {
            if !engine.isRunning { try engine.start() }
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
            playbackMessage = "لم يتم العثور على أغنية قابلة للتشغيل."
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

    private func updateProgress() {
        guard isPlaying, !isSeeking else { return }
        let now = Date()
        elapsed = min(duration, elapsed + now.timeIntervalSince(lastProgressDate) * Double(speed))
        lastProgressDate = now
        if elapsed >= duration { elapsed = duration }
        let fadeDuration = min(crossfadeSeconds, duration / 2)
        if fadeDuration > 0 {
            let fadeIn = min(1, max(0, elapsed / fadeDuration))
            let fadeOut = min(1, max(0, (duration - elapsed) / fadeDuration))
            fxMixer.outputVolume = Float(min(fadeIn, fadeOut))
        } else {
            fxMixer.outputVolume = 1
        }
    }

    private func applyPlaybackRate() {
        let rate = max(0.25, min(4, speed))
        if keepPitch { varispeed.rate = 1; timePitch.rate = rate }
        else { varispeed.rate = rate; timePitch.rate = 1 }
    }

    private func updateNowPlaying() {
        guard let item = currentItem else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title ?? "بدون عنوان",
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
        routeName = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "لا يوجد مسار"
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
            eqGains = settings.gains.count == 5 ? settings.gains : Array(repeating: 0, count: 5)
            preamp = settings.globalGain
            selectedPreset = settings.preset
        } else { eqGains = [0, 0, 0, 0, 0]; preamp = 0; selectedPreset = .flat }
        applyEQSettings()
    }

    private func saveSettingsForCurrentRoute() {
        var values = storedSettings()
        values[routeKey()] = EQSettings(gains: eqGains, globalGain: preamp, preset: selectedPreset)
        if let data = try? JSONEncoder().encode(values) { UserDefaults.standard.set(data, forKey: userDefaultsKey) }
    }

    private func loadSpeed(for item: MPMediaItem) -> Float {
        let values = UserDefaults.standard.dictionary(forKey: speedDefaultsKey) as? [String: Double] ?? [:]
        let stored = values[String(item.persistentID)] ?? 1
        return Float(max(0.25, min(4, stored)))
    }

    private func saveSpeedForCurrentTrack() {
        guard let item = currentItem else { return }
        var values = UserDefaults.standard.dictionary(forKey: speedDefaultsKey) as? [String: Double] ?? [:]
        values[String(item.persistentID)] = Double(speed)
        UserDefaults.standard.set(values, forKey: speedDefaultsKey)
    }

    private func applyEQSettings() {
        for index in eq.bands.indices where index < eqGains.count { eq.bands[index].gain = eqGains[index]; eq.bands[index].bypass = false }
        eq.globalGain = preamp
    }
}
