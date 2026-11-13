import SwiftUI
import MediaPlayer
import UIKit

struct ContentView: View {
    @EnvironmentObject private var library: MediaLibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var favorites: FavoritesStore
    @State private var selectedTab: AppTab = .player
    @State private var showQueue = false
    @State private var searchText = ""
    @State private var favoritesOnly = false
    @State private var sortOption: LibrarySortOption = .title
    @AppStorage("ew27.vinyl.enabled") private var vinylMode = false
    @State private var showFullScreen = false
    @State private var showLyrics = false
    @State private var albumArtMotion = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let speedPresets: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    private enum AppTab: Hashable, CaseIterable {
        case player
        case library
        case sound

        var title: String {
            switch self { case .player: return "Listen"; case .library: return "Library"; case .sound: return "Studio" }
        }

        var icon: String {
            switch self { case .player: return "waveform"; case .library: return "square.stack"; case .sound: return "slider.horizontal.3" }
        }
    }

    private enum LibrarySortOption: String, CaseIterable, Identifiable {
        case title = "Title"
        case artist = "Artist"
        case album = "Album"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .player: playerTab
                case .library: libraryTab
                case .sound: soundTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            appTabDock
        }
        .overlay(alignment: .top) { RouteAccessoryCard(routeName: player.routeName) }
        .sheet(isPresented: $showQueue) { QueueView(player: player) }
        .sheet(isPresented: $showFullScreen) { NowPlayingFullView(player: player) }
        .sheet(isPresented: $showLyrics) { LyricsView(player: player, store: player.lyricsStore) }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: selectedTab)
        .onAppear { startAlbumArtMotion() }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { albumArtMotion = false } else { startAlbumArtMotion() }
        }
    }

    private var appTabDock: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases, id: \.self) { item in
                let selected = selectedTab == item
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) { selectedTab = item }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .symbolEffect(.bounce, value: selected)
                        if selected {
                            Text(item.title).font(.caption.weight(.bold)).transition(.opacity.combined(with: .scale(scale: 0.86)))
                        }
                    }
                    .foregroundStyle(selected ? Color.cyan : Color.white.opacity(0.56))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background {
                        if selected { Capsule().fill(.white.opacity(0.105)).overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1)) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(MusicPressStyle())
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.13), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 7)
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 5)
        .background(.clear)
    }

    private func startAlbumArtMotion() {
        guard !reduceMotion else { albumArtMotion = false; return }
        withAnimation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true)) { albumArtMotion = true }
    }

    private var playerTab: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                playerSection
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity)
            }
            .background { ArtworkAuroraBackground(image: player.currentArtwork, tint: player.artworkTint) }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var libraryTab: some View {
        NavigationStack {
            appList {
                libraryOverviewSection
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
    }

    private var soundTab: some View {
        NavigationStack {
            appList {
                soundOverviewSection
                eqSection
                AudioEffectsSection(player: player)
                SettingsSection(player: player)
            }
            .navigationTitle("Sound")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func appList<Content: View>(@ViewBuilder content: () -> Content) -> some View {
            List { content() }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background {
                ArtworkAuroraBackground(image: player.currentArtwork, tint: player.artworkTint)
            }
            .listRowBackground(Color.white.opacity(0.028))
            .listRowSeparator(.hidden)
            .tint(Color(red: 0.38, green: 0.78, blue: 1))
            .buttonStyle(MusicPressStyle())
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

    private var libraryOverviewSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "square.stack.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .frame(width: 52, height: 52)
                    .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("YOUR COLLECTION").font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(.cyan)
                    Text("\(library.allSongs.count) songs · \(library.playlists.count) playlists")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                }
                Spacer(minLength: 0)
                Image(systemName: "waveform").font(.system(size: 19, weight: .medium)).foregroundStyle(.white.opacity(0.4))
            }
            .padding(16)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.09), lineWidth: 1))
            .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    private var soundOverviewSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .frame(width: 52, height: 52)
                    .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("SOUND STUDIO").font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(.cyan)
                    Text("\(player.activeEQProfileName ?? "Flat") · \(player.reverbMode) reverb")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                }
                Spacer(minLength: 0)
                Circle().fill(player.eqEnabled ? Color.green : Color.white.opacity(0.30)).frame(width: 8, height: 8)
            }
            .padding(16)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.09), lineWidth: 1))
            .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
            .listRowBackground(Color.clear)
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
            .buttonStyle(MusicPressStyle())
            Button { player.nextTrack() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 38)
            }
            .buttonStyle(MusicPressStyle())
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
        VStack(alignment: .leading, spacing: 22) {
            deckHeader
            deckIdentity
            deckProgress
            deckTransport
            deckShortcuts
            deckTuning
            if let message = player.playbackMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var deckHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("EW27  /  LISTENING DECK")
                    .font(.caption2.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(.cyan)
                Text(player.isPlaying ? "In the moment" : "Your music")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            Spacer()
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.09), in: Circle())
            }
            .buttonStyle(MusicPressStyle())
            .accessibilityLabel("Open queue")
            Menu {
                Toggle("Vinyl artwork", isOn: $vinylMode)
                Toggle("Keep pitch", isOn: Binding(get: { player.keepPitch }, set: { player.keepPitch = $0; player.setSpeed(player.speed) }))
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.09), in: Circle())
            }
            .accessibilityLabel("Playback options")
        }
    }

    private var deckIdentity: some View {
        HStack(spacing: 16) {
            playerArtwork
                .frame(width: 124, height: 124)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                .scaleEffect(!reduceMotion && player.isPlaying && albumArtMotion ? 1.035 : 1)
                .rotation3DEffect(.degrees(!reduceMotion && player.isPlaying && albumArtMotion ? 2 : 0), axis: (x: 0, y: 1, z: 0))
                .id(player.currentItem?.persistentID)
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
                .animation(.spring(response: 0.55, dampingFraction: 0.78), value: player.currentItem?.persistentID)
                .onTapGesture { showFullScreen = true }

            VStack(alignment: .leading, spacing: 7) {
                Text(player.currentItem?.title ?? "Nothing playing")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(player.currentItem?.artist ?? "Choose a track in your library")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Circle().fill(player.isPlaying ? Color.green : Color.white.opacity(0.35)).frame(width: 6, height: 6)
                    Text(player.isPlaying ? "PLAYING" : "READY")
                        .font(.caption2.weight(.bold)).tracking(1.1)
                    Text("·  \(player.audioQualityLabel)")
                        .font(.caption2).lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
            if let item = player.currentItem {
                let isFavorite = favorites.contains(item)
                Button { favorites.toggle(item) } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isFavorite ? Color.pink : Color.white.opacity(0.76))
                }
                .buttonStyle(MusicPressStyle())
                .accessibilityLabel(isFavorite ? "Remove Favorite" : "Add to Favorites")
            }
        }
        .padding(14)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
    }

    private var deckProgress: some View {
        VStack(spacing: 10) {
            WaveformView(store: player.waveformStore, clock: player.clock) { player.seek(to: $0) }
                .frame(height: 54)
            PlaybackTimeLabels(clock: player.clock)
        }
        .padding(.horizontal, 2)
    }

    private var deckTransport: some View {
        HStack(spacing: 0) {
            Button { player.shuffleEnabled.toggle() } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(player.shuffleEnabled ? Color.cyan : Color.white.opacity(0.48))
                    .frame(width: 34, height: 56)
            }
            .buttonStyle(MusicPressStyle())
            Spacer(minLength: 2)
            playerActionButton("backward.end.fill", label: "Previous track", size: 20) { player.previousTrack() }
            Spacer(minLength: 2)
            Button { haptic(); player.togglePlayPause() } label: {
                HStack(spacing: 9) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .bold))
                    Text(player.isPlaying ? "PAUSE" : "PLAY")
                        .font(.caption.weight(.heavy)).tracking(1.3)
                }
                .foregroundStyle(Color(red: 0.03, green: 0.07, blue: 0.11))
                .frame(width: 100, height: 56)
                .background(Capsule().fill(Color.cyan.gradient))
                .shadow(color: .cyan.opacity(0.24), radius: 15, y: 6)
            }
            .buttonStyle(MusicPressStyle())
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Spacer(minLength: 2)
            playerActionButton("forward.end.fill", label: "Next track", size: 20) { haptic(); player.nextTrack() }
            Spacer(minLength: 2)
            Button { showLyrics = true } label: {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 34, height: 56)
            }
            .buttonStyle(MusicPressStyle())
            .disabled(player.currentItem == nil)
            .accessibilityLabel("Open lyrics")
        }
    }

    private var deckShortcuts: some View {
        HStack(spacing: 12) {
            listeningCard(title: "UP NEXT", value: nextTrackTitle, icon: "text.line.first.and.arrowtriangle.forward") {
                showQueue = true
            }
            listeningCard(title: "OUTPUT", value: player.routeName, icon: "airplay.audio") {
                showFullScreen = true
            }
        }
    }

    private var deckTuning: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("QUICK TUNING").font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text(String(format: "%.2f×", player.speed)).font(.caption.monospacedDigit().weight(.bold)).foregroundStyle(.cyan)
            }
            HStack(spacing: 10) {
                ForEach(speedPresets, id: \.self) { value in
                    Button(String(format: "%g×", value)) { player.setSpeed(value) }
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(abs(player.speed - value) < 0.02 ? Color.black : .white.opacity(0.76))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(abs(player.speed - value) < 0.02 ? Color.cyan : Color.white.opacity(0.07), in: Capsule())
                }
            }
            DisclosureGroup {
                PlaybackControlsView(player: player, clock: player.clock, speedState: player.speedState, spectrum: player.spectrumModel, waveform: player.waveformStore)
                    .padding(.top, 12)
            } label: {
                Label("Advanced playback", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .tint(.cyan)
        }
        .padding(16)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.075), lineWidth: 1))
    }

    private var nextTrackTitle: String {
        guard player.queue.indices.contains(player.currentIndex + 1) else { return "Queue & shuffle" }
        return player.queue[player.currentIndex + 1].title ?? "Untitled"
    }

    private func listeningCard(title: String, value: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(.white.opacity(0.46))
                    Text(value).font(.caption.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.35))
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(MusicPressStyle())
    }

    private func playerActionButton(_ symbol: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 48)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(MusicPressStyle())
        .accessibilityLabel(label)
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
                let visibleSongs = filteredSongs
                let playableQueue = library.playableItems(visibleSongs)
                ForEach(visibleSongs, id: \.persistentID) { item in
                    trackRow(item, queue: playableQueue)
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
                        let playableQueue = library.playableItems(items)
                        ForEach(items, id: \.persistentID) { item in
                            trackRow(item, queue: playableQueue)
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
            if item.assetURL != nil { haptic(); player.play(item, queue: queue) }
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
                        .lineLimit(1)
                    Text(item.artist ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if item.assetURL == nil {
                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                } else if isCurrent {
                    Image(systemName: "waveform").font(.caption.weight(.bold)).foregroundStyle(.cyan)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isCurrent ? Color.cyan.opacity(0.075) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(MusicPressStyle())
        .listRowInsets(EdgeInsets(top: 3, leading: 14, bottom: 3, trailing: 14))
        .listRowBackground(Color.clear)
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
        if sortOption == .title { return matchingSongs }
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

    private func haptic() {
        let enabled = UserDefaults.standard.object(forKey: "ew27.haptics.enabled") as? Bool ?? true
        if enabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }
}
