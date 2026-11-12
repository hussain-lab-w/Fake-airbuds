import SwiftUI
import MediaPlayer
import UIKit

struct ContentView: View {
    @EnvironmentObject private var library: MediaLibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var favorites: FavoritesStore
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false
    @State private var selectedTab: AppTab = .library
    @State private var showQueue = false
    @State private var searchText = ""
    @State private var favoritesOnly = false
    @State private var sortOption: LibrarySortOption = .title
    @AppStorage("ew27.vinyl.enabled") private var vinylMode = false
    @State private var showFullScreen = false
    @State private var showLyrics = false

    private let speedPresets: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    private enum AppTab: Hashable {
        case player
        case library
        case sound
    }

    private enum LibrarySortOption: String, CaseIterable, Identifiable {
        case title = "Title"
        case artist = "Artist"
        case album = "Album"
        var id: String { rawValue }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            playerTab
            libraryTab
            soundTab
        }
        .tint(Color(red: 0.38, green: 0.78, blue: 1))
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .overlay(alignment: .top) { RouteAccessoryCard(routeName: player.routeName) }
        .sheet(isPresented: $showQueue) { QueueView(player: player) }
        .sheet(isPresented: $showFullScreen) { NowPlayingFullView(player: player) }
        .sheet(isPresented: $showLyrics) { LyricsView(player: player, store: player.lyricsStore) }
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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort by", selection: $sortOption) {
                            ForEach(LibrarySortOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Sort songs")
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
                SettingsSection(player: player)
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
                ArtworkAuroraBackground(image: player.currentArtwork, tint: player.artworkTint)
            }
            .listRowBackground(Color.white.opacity(0.028))
            .listRowSeparatorTint(Color.white.opacity(0.055))
            .tint(Color(red: 0.38, green: 0.78, blue: 1))
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .animation(.easeInOut(duration: 0.24), value: player.currentItem?.persistentID)
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
            MiniProgressLine(clock: player.clock)
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
        .shadow(color: .black.opacity(0.32), radius: 14, y: 7)
        .contentShape(Rectangle())
        .onTapGesture { showFullScreen = true }
    }

    @ViewBuilder
    private var playerArtwork: some View {
        if vinylMode {
            VinylView(image: player.currentArtwork, isPlaying: player.isPlaying, speed: player.speed)
        } else if let artwork = player.currentArtwork {
            Image(uiImage: artwork).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            ZStack {
                LinearGradient(colors: [Color.cyan.opacity(0.75), Color.blue.opacity(0.38), Color.purple.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "waveform").font(.system(size: 38, weight: .medium)).foregroundStyle(.white.opacity(0.92))
            }.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var playerSection: some View {
        Section {
            VStack(spacing: 20) {
                playerArtwork
                    .frame(maxWidth: 320)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.30), radius: 24, y: 12)
                    .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .onTapGesture { showFullScreen = true }

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.currentItem?.title ?? "No track selected")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                        Text(player.currentItem?.artist ?? "Choose a song from your library")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let item = player.currentItem {
                        let isFavorite = favorites.contains(item)
                        Button { favorites.toggle(item) } label: {
                            Image(systemName: isFavorite ? "heart.fill" : "heart")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(isFavorite ? Color.pink : Color.primary.opacity(0.78))
                                .frame(width: 44, height: 44)
                                .background(.thinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isFavorite ? "Remove Favorite" : "Add to Favorites")
                    }
                }

                VStack(spacing: 8) {
                    WaveformView(store: player.waveformStore, clock: player.clock) { player.seek(to: $0) }
                    HStack {
                        Text(formatTime(player.elapsed))
                        Spacer()
                        Label(player.routeName, systemImage: "airplay.audio")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer()
                        Text(formatTime(player.duration))
                    }
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 0) {
                    playerActionButton("backward.end.fill", label: "Previous track", size: 23) { player.previousTrack() }
                    Spacer()
                    Button { haptic(); player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 23, weight: .bold))
                            .offset(x: player.isPlaying ? 0 : 2)
                            .foregroundStyle(Color(red: 0.015, green: 0.06, blue: 0.12))
                            .frame(width: 72, height: 72)
                            .background(Circle().fill(Color.cyan.gradient))
                            .shadow(color: .cyan.opacity(0.25), radius: 16, y: 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                    Spacer()
                    playerActionButton("forward.end.fill", label: "Next track", size: 23) { haptic(); player.nextTrack() }
                }
                .padding(.horizontal, 14)

                HStack(spacing: 10) {
                    playerUtilityButton("Up Next", icon: "text.line.first.and.arrowtriangle.forward") { showQueue = true }
                    playerUtilityButton("Lyrics", icon: "quote.bubble") { showLyrics = true }
                        .disabled(player.currentItem == nil)
                    Menu {
                        Toggle("Shuffle", isOn: $player.shuffleEnabled)
                        Toggle("Vinyl artwork", isOn: $vinylMode)
                        Toggle("Keep pitch", isOn: Binding(get: { player.keepPitch }, set: { player.keepPitch = $0; player.setSpeed(player.speed) }))
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .background(.thinMaterial, in: Circle())
                    }
                    .accessibilityLabel("More playback options")
                }

                DisclosureGroup {
                    PlaybackControlsView(player: player, clock: player.clock, speedState: player.speedState, spectrum: player.spectrumModel, waveform: player.waveformStore)
                        .padding(.top, 12)
                } label: {
                    Label("Playback tools", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if let message = player.playbackMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 22, y: 10)
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 12, trailing: 12))
            .listRowBackground(Color.clear)
        } header: {
            HStack {
                Text("NOW PLAYING")
                    .font(.caption2.weight(.bold))
                    .tracking(1.3)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: player.isPlaying ? "waveform.circle.fill" : "waveform.circle")
                    .foregroundStyle(.cyan.opacity(0.75))
            }
            .textCase(nil)
        }
    }

    private func playerActionButton(_ symbol: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 52, height: 52)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func playerUtilityButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
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
                EQSliderControl(player: player, index: nil, title: "Preamp")

                Button { player.resetEQ() } label: {
                    Label("Reset to Flat", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.cyan)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
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
        Section("All Songs") {
            if library.allSongs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.cyan)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(.cyan.opacity(0.12)))
                    Text(library.message ?? "No songs.")
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
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
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
        let matchingSongs = library.allSongs.filter { item in
            let fields = [item.title, item.artist, item.albumTitle].compactMap { $0 }
            let matchesText = searchText.isEmpty || fields.contains { $0.localizedCaseInsensitiveContains(searchText) }
            return matchesText && (!favoritesOnly || favorites.contains(item))
        }
        return matchingSongs.sorted { left, right in
            let leftValue: String
            let rightValue: String
            switch sortOption {
            case .title:
                leftValue = left.title ?? ""
                rightValue = right.title ?? ""
            case .artist:
                leftValue = left.artist ?? ""
                rightValue = right.artist ?? ""
            case .album:
                leftValue = left.albumTitle ?? ""
                rightValue = right.albumTitle ?? ""
            }
            return leftValue.localizedCaseInsensitiveCompare(rightValue) == .orderedAscending
        }
    }

    private func eqSlider(index: Int, title: String) -> some View {
        EQSliderControl(player: player, index: index, title: title)
    }

    private func formatTime(_ value: TimeInterval) -> String {
        guard value.isFinite else { return "0:00" }
        let total = max(0, Int(value.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func haptic() {
        let enabled = UserDefaults.standard.object(forKey: "ew27.haptics.enabled") as? Bool ?? true
        if enabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }
}
