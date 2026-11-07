import SwiftUI
import MediaPlayer
import UIKit

struct ContentView: View {
    @EnvironmentObject private var library: MediaLibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var favorites: FavoritesStore
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false
    @State private var selectedTab: AppTab = .player
    @State private var showQueue = false
    @State private var searchText = ""
    @State private var favoritesOnly = false
    @State private var vinylMode = false

    private let speedPresets: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    private enum AppTab: Hashable {
        case player
        case library
        case sound
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            playerTab
            libraryTab
            soundTab
        }
        .tint(Color(red: 0.38, green: 0.78, blue: 1))
        .overlay(alignment: .top) { RouteAccessoryCard(routeName: player.routeName) }
        .onChange(of: player.elapsed) { _, value in
            if !isScrubbing { scrubValue = value }
        }
        .sheet(isPresented: $showQueue) { QueueView(player: player) }
        .preferredColorScheme(.dark)
    }

    private var playerTab: some View {
        NavigationStack {
            appList { playerSection }
                .navigationTitle("Now Playing")
                .navigationBarTitleDisplayMode(.inline)
        }
        .tabItem { Label("Player", systemImage: "waveform") }
        .tag(AppTab.player)
    }

    private var libraryTab: some View {
        NavigationStack {
            appList {
                Toggle("Favorites only", isOn: $favoritesOnly)
                allSongsSection
                playlistsSection
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Title, artist, or album")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await library.requestAccessAndLoad() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                }
            }
        }
        .tabItem { Label("Library", systemImage: "music.note.list") }
        .tag(AppTab.library)
    }

    private var soundTab: some View {
        NavigationStack {
            appList {
                eqSection
                AudioEffectsSection(player: player)
            }
            .navigationTitle("Sound")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tabItem { Label("Sound", systemImage: "slider.horizontal.3") }
        .tag(AppTab.sound)
    }

    private func appList<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        List { content() }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background {
                LinearGradient(
                    colors: [Color(red: 0.035, green: 0.055, blue: 0.12), Color(red: 0.075, green: 0.07, blue: 0.17), Color(red: 0.025, green: 0.04, blue: 0.095)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ).ignoresSafeArea()
            }
            .listRowBackground(Color.white.opacity(0.045))
            .listRowSeparatorTint(Color.white.opacity(0.08))
            .tint(Color(red: 0.38, green: 0.78, blue: 1))
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color(red: 0.035, green: 0.055, blue: 0.12), for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if player.currentItem != nil && selectedTab != .player {
                    miniPlayer
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
            }
    }

    private var miniPlayer: some View {
        HStack(spacing: 12) {
            Group {
                if let artwork = ArtworkCache.shared.image(for: player.currentItem?.persistentID ?? 0, artwork: player.currentItem?.artwork, size: CGSize(width: 96, height: 96)) {
                    Image(uiImage: artwork).resizable().scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(colors: [.cyan.opacity(0.8), .blue.opacity(0.55), .purple.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "waveform").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    }
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentItem?.title ?? "No track selected")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(player.currentItem?.artist ?? "EW27 Player")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let remaining = player.sleepRemaining {
                    Text(String(format: "Sleep %.0fs", remaining)).font(.caption2).foregroundStyle(.cyan)
                }
            }
            Spacer(minLength: 4)
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.cyan.opacity(0.18)))
                    .foregroundStyle(.cyan)
            }
            .buttonStyle(.plain)
            Button { player.nextTrack() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 38)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))
        .overlay(alignment: .bottom) {
            GeometryReader { proxy in
                let progress = player.duration > 0 ? CGFloat(min(1, max(0, player.elapsed / player.duration))) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 2)
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
        .shadow(color: .black.opacity(0.32), radius: 14, y: 7)
    }

    private var playerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 16) {
                    Group {
                        if let artwork = player.currentArtwork {
                            Image(uiImage: artwork)
                                .resizable()
                                .scaledToFill()
                        } else {
                            ZStack {
                                LinearGradient(colors: [Color.cyan.opacity(0.75), Color.blue.opacity(0.38), Color.purple.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                Image(systemName: "waveform")
                                    .font(.system(size: 38, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.92))
                            }
                        }
                    }
                    .frame(width: 106, height: 106)
                    .clipShape(vinylMode ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 20, style: .continuous)))
                    .rotationEffect(.degrees(vinylMode && player.isPlaying ? player.elapsed * 24 * Double(player.speed) : 0))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))
                    .shadow(color: .black.opacity(0.28), radius: 12, y: 7)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(player.currentItem?.title ?? "No track selected")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .minimumScaleFactor(0.82)
                        Text(player.currentItem?.artist ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(1)
                        Label(player.routeName, systemImage: "airplay.audio")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.cyan.opacity(0.95))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 22) {
                    Button { player.previousTrack() } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(.white.opacity(0.09)))
                    }
                    Spacer()
                    Button { haptic(); player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 25, weight: .bold))
                            .offset(x: player.isPlaying ? 0 : 2)
                            .frame(width: 72, height: 72)
                            .background(Circle().fill(LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing)))
                            .foregroundStyle(Color(red: 0.02, green: 0.08, blue: 0.16))
                            .shadow(color: .cyan.opacity(0.28), radius: 14, y: 5)
                    }
                    Spacer()
                    Button { haptic(); player.nextTrack() } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(.white.opacity(0.09)))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)

                SpectrumView(bars: player.spectrumBars)

                VStack(spacing: 2) {
                    Slider(value: $scrubValue, in: 0...max(1, player.duration), onEditingChanged: { editing in
                        isScrubbing = editing
                        if !editing { player.seek(to: scrubValue) }
                    })
                    .tint(.cyan)
                    HStack {
                        Text(formatTime(isScrubbing ? scrubValue : player.elapsed))
                        Spacer()
                        Text(formatTime(player.duration))
                    }
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(.white.opacity(0.58))
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Speed", systemImage: "speedometer")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(String(format: "%.2fx", player.speed))
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(.cyan)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(speedPresets, id: \.self) { value in
                            let selected = abs(player.speed - value) < 0.02
                            Button(String(format: "%g×", value)) { haptic(); player.setSpeed(value) }
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(selected ? Color.cyan.opacity(0.22) : Color.white.opacity(0.07)))
                                .overlay(Capsule().stroke(selected ? Color.cyan.opacity(0.65) : Color.white.opacity(0.08), lineWidth: 1))
                                .foregroundStyle(selected ? .cyan : .white.opacity(0.8))
                                .buttonStyle(.plain)
                        }
                    }
                    Slider(value: Binding(get: { Double(player.speed) }, set: { player.setSpeed(Float($0)) }), in: 0.25...4)
                        .tint(.cyan)
                }

                HStack(spacing: 16) {
                    Button { showQueue = true } label: { Label("Up Next", systemImage: "list.bullet") }
                        .buttonStyle(.bordered)
                    Toggle("Keep pitch", isOn: $player.keepPitch)
                        .onChange(of: player.keepPitch) { _, _ in player.setSpeed(player.speed) }
                    Toggle("Shuffle", isOn: $player.shuffleEnabled)
                }
                .font(.caption.weight(.medium))
                .tint(.cyan)
                Toggle("Vinyl mode", isOn: $vinylMode)
                    .font(.caption.weight(.medium))
                    .tint(.cyan)

                if let message = player.playbackMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("When a track ends, press play to restart it or use Next.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.52))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Color(red: 0.10, green: 0.15, blue: 0.27), Color(red: 0.09, green: 0.10, blue: 0.21)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 12, trailing: 12))
            .listRowBackground(Color.clear)
        } header: {
            HStack {
                Label("Player", systemImage: "waveform")
                    .font(.caption.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(.cyan)
                Spacer()
                Image(systemName: player.isPlaying ? "waveform.circle.fill" : "waveform.circle")
                    .foregroundStyle(.cyan.opacity(0.75))
            }
            .textCase(nil)
        }
    }

    private var eqSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Preset", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Toggle("EQ On", isOn: Binding(get: { player.eqEnabled }, set: { player.setEQEnabled($0) }))
                        .labelsHidden()
                    Picker("Preset", selection: Binding(get: { player.selectedPreset }, set: { player.applyPreset($0) })) {
                        ForEach(AudioPlayer.Preset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.cyan)
                }

                Divider().overlay(.white.opacity(0.08))

                EQCurveView(frequencies: [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000], gains: player.eqGains, profileName: player.activeEQProfileName)
                ForEach(Array(zip(["31 Hz", "62 Hz", "125 Hz", "250 Hz", "500 Hz", "1 kHz", "2 kHz", "4 kHz", "8 kHz", "16 kHz"], 0..<10)), id: \.1) { title, index in
                    eqSlider(index: index, title: title)
                }
                eqSlider(title: "Preamp", value: Binding(get: { player.preamp }, set: { player.setPreamp($0) }))

                Button { player.resetEQ() } label: {
                    Label("Reset to Flat", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.cyan)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Color(red: 0.10, green: 0.15, blue: 0.27), Color(red: 0.09, green: 0.10, blue: 0.21)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(0.20), radius: 14, y: 7)
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 12, trailing: 12))
            .listRowBackground(Color.clear)
        } header: {
            Label("Equalizer", systemImage: "waveform.path.ecg")
                .font(.caption.weight(.bold))
                .tracking(1)
                .foregroundStyle(.cyan)
                .textCase(nil)
        }
    }

    private var allSongsSection: some View {
        Section("All Local Songs") {
            if library.allSongs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.cyan)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(.cyan.opacity(0.12)))
                    Text(library.message ?? "No local songs.")
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredSongs, id: \.persistentID) { item in
                    trackRow(item, queue: library.playableItems(filteredSongs))
                }
            }
        }
    }

    private var playlistsSection: some View {
        Section("Playlists") {
            if library.playlists.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 27, weight: .medium))
                        .foregroundStyle(.cyan)
                    Text("No local playlists, or permission not granted.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .listRowBackground(Color.clear)
            } else {
                ForEach(library.playlists, id: \.persistentID) { playlist in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { library.selectedPlaylistID == playlist.persistentID },
                            set: { if $0 { library.selectedPlaylistID = playlist.persistentID } }
                        )
                    ) {
                        let items = library.items(in: playlist)
                        ForEach(items, id: \.persistentID) { item in
                            trackRow(item, queue: library.playableItems(items))
                        }
                    } label: {
                        Text(playlist.value(forProperty: MPMediaPlaylistPropertyName) as? String ?? "Playlist")
                    }
                }
            }
        }
    }

    private func trackRow(_ item: MPMediaItem, queue: [MPMediaItem]) -> some View {
        let isCurrent = player.currentItem?.persistentID == item.persistentID
        return Button {
            if item.assetURL != nil { player.play(item, queue: queue) }
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let artwork = ArtworkCache.shared.image(for: item.persistentID, artwork: item.artwork, size: CGSize(width: 120, height: 120)) {
                        Image(uiImage: artwork).resizable().scaledToFill()
                    } else {
                        ZStack {
                            LinearGradient(colors: [.cyan.opacity(0.52), .indigo.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            Image(systemName: isCurrent ? "waveform" : "music.note")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title ?? "Untitled")
                        .font(.subheadline.weight(isCurrent ? .semibold : .medium))
                        .foregroundStyle(isCurrent ? .cyan : .primary)
                    Text(item.artist ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if item.assetURL == nil {
                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                } else if isCurrent {
                    Image(systemName: "waveform").font(.caption.weight(.bold)).foregroundStyle(.cyan)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(item.assetURL == nil)
        .contextMenu {
            Button { player.addToQueue(item, playNext: true) } label: { Label("Play Next", systemImage: "text.insert") }
            Button { player.addToQueue(item) } label: { Label("Add to Queue", systemImage: "text.append") }
            Button { favorites.toggle(item) } label: { Label(favorites.contains(item) ? "Remove Favorite" : "Favorite", systemImage: favorites.contains(item) ? "heart.slash" : "heart") }
        }
    }

    private var filteredSongs: [MPMediaItem] {
        library.allSongs.filter { item in
            let fields = [item.title, item.artist, item.albumTitle].compactMap { $0 }
            let matchesText = searchText.isEmpty || fields.contains { $0.localizedCaseInsensitiveContains(searchText) }
            return matchesText && (!favoritesOnly || favorites.contains(item))
        }
    }

    private func eqSlider(index: Int, title: String) -> some View {
        eqSlider(title: title, value: Binding(
            get: { player.eqGains.indices.contains(index) ? player.eqGains[index] : 0 },
            set: { player.setBandGain(index: index, gain: $0) }
        ))
    }

    private func eqSlider(title: String, value: Binding<Float>) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%+.1f dB", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: -12...12, step: 0.5)
        }
    }

    private func formatTime(_ value: TimeInterval) -> String {
        guard value.isFinite else { return "0:00" }
        let total = max(0, Int(value.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func haptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
