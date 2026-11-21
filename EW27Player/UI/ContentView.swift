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
    @State private var showLyrics = false
    @State private var showPlaybackSettings = false
    @State private var albumArtMotion = false
    @State private var dockVisible = true
    @State private var lastScrollOffset: CGFloat = 0
    @AppStorage("ew27.appearance") private var appearanceRawValue = EW27Appearance.system.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var playerNamespace

    private let speedPresets: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    private enum AppTab: Hashable, CaseIterable {
        case player
        case library
        case sound

        var title: String {
            switch self { case .player: return "Player"; case .library: return "Library"; case .sound: return "Studio" }
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
            .id(selectedTab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            if player.currentItem != nil && selectedTab != .player && dockVisible {
                miniPlayer
                    .padding(.horizontal, 14)
                    .padding(.top, 7)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if dockVisible {
                appTabDock
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onPreferenceChange(DockScrollOffsetKey.self) { offset in
            defer { lastScrollOffset = offset }
            guard selectedTab != .player, !showLyrics else { return }
            let delta = offset - lastScrollOffset
            guard abs(delta) > 6 else { return }
            let shouldShow = delta > 0
            guard shouldShow != dockVisible else { return }
            withAnimation(reduceMotion ? nil : Motion.microInteraction) { dockVisible = shouldShow }
        }
        .overlay(alignment: .top) { RouteAccessoryCard(routeName: player.routeName) }
        .sheet(isPresented: $showQueue) {
            QueueView(player: player)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(EW27Radius.panel)
        }
        .preferredColorScheme(EW27Appearance(rawValue: appearanceRawValue)?.colorScheme)
        .tint(EW27Design.accent)
        .sensoryFeedback(.selection, trigger: selectedTab)
        .onAppear { startAlbumArtMotion() }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { albumArtMotion = false } else { startAlbumArtMotion() }
        }
        .animation(reduceMotion ? nil : Motion.crossfade, value: selectedTab)
        .onChange(of: selectedTab) { _, _ in
            if !dockVisible {
                withAnimation(reduceMotion ? nil : Motion.microInteraction) { dockVisible = true }
            }
        }
    }

    private var appTabDock: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases, id: \.self) { item in
                let selected = selectedTab == item
                Button {
                    withAnimation(reduceMotion ? nil : Motion.microInteraction) { selectedTab = item }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .symbolEffect(.bounce, value: reduceMotion ? 0 : (selected ? 1 : 0))
                        if selected {
                            Text(item.title).font(.caption.weight(.bold)).transition(.opacity.combined(with: .scale(scale: 0.86)))
                        }
                    }
                    .foregroundStyle(selected ? EW27Design.accent : EW27Design.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background {
                        if selected {
                            Capsule()
                                .fill(EW27Design.accent.opacity(0.13))
                                .overlay(Capsule().stroke(EW27Design.accent.opacity(0.28), lineWidth: 1))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(MusicPressStyle())
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(7)
        .liquidGlass(prominent: true, translucent: true)
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func startAlbumArtMotion() {
        guard !reduceMotion else { albumArtMotion = false; return }
        withAnimation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true)) { albumArtMotion = true }
    }

    private var playerTab: some View {
        NavigationStack {
            ZStack {
                ArtworkAuroraBackground(image: player.currentArtwork, tint: player.artworkTint)
                if showLyrics {
                    LyricsView(player: player, store: player.lyricsStore, onReturnToPlayer: {
                        setLyricsVisible(false)
                    })
                    .transition(lyricsTransition(edge: .trailing))
                } else {
                    playerSection
                    .transition(lyricsTransition(edge: .leading))
                }
            }
            .animation(Motion.transition, value: showLyrics)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showPlaybackSettings) {
                NavigationStack {
                    ScrollView(showsIndicators: false) {
                        deckTuning
                            .padding(20)
                    }
                    .navigationTitle("Playback settings")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(30)
            }
        }
    }

    private func lyricsTransition(edge: Edge) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.975)),
            removal: .opacity.combined(with: .scale(scale: 1.02))
        )
    }

    private func setLyricsVisible(_ visible: Bool) {
        withAnimation(Motion.transition) {
            showLyrics = visible
        }
    }

    private var libraryTab: some View {
        NavigationStack {
            appList {
                libraryOverviewSection
                librarySpotlightSection
                libraryFilterSection
                allSongsSection
                playlistsSection
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Title, artist, or album"
            )
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

    private var libraryFilterSection: some View {
        Section {
            HStack(spacing: 8) {
                libraryFilterButton(title: "All songs", count: library.allSongs.count, isSelected: !favoritesOnly) {
                    favoritesOnly = false
                }
                libraryFilterButton(title: "Favorites", count: library.allSongs.filter { favorites.contains($0) }.count, isSelected: favoritesOnly) {
                    favoritesOnly = true
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
            .listRowBackground(Color.clear)
        }
    }

    private func libraryFilterButton(title: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Text("\(count)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .opacity(0.72)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? Color.black : EW27Design.primaryText.opacity(0.68))
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .glassChip(isSelected: isSelected)
        }
        .buttonStyle(MusicPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var soundTab: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    studioHeaderSection
                    studioToolsSummary
                    AudioEffectsSection(player: player)
                    eqSection
                    SettingsSection(player: player)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 92)
            }
            .background { ArtworkAuroraBackground(image: player.currentArtwork, tint: player.artworkTint) }
            .coordinateSpace(name: "ew27.dockScroll")
            .dockScrollTracking()
            .scrollBounceBehavior(.basedOnSize)
            .buttonStyle(MusicPressStyle())
            .tint(Color(red: 0.38, green: 0.78, blue: 1))
            .navigationTitle("Studio")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func appList<Content: View>(@ViewBuilder content: () -> Content) -> some View {
            List { content() }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .coordinateSpace(name: "ew27.dockScroll")
            .dockScrollTracking()
            .background {
                ArtworkAuroraBackground(image: player.currentArtwork, tint: player.artworkTint)
            }
            .listRowBackground(EW27Design.primaryText.opacity(0.028))
            .listRowSeparator(.hidden)
            .tint(Color(red: 0.38, green: 0.78, blue: 1))
            .buttonStyle(MusicPressStyle())
    }

    private var libraryOverviewSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "square.stack.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .frame(width: 52, height: 52)
                    .glassRow(radius: 16)
                VStack(alignment: .leading, spacing: 4) {
                    Text("YOUR COLLECTION").font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(.cyan)
                    Text("\(library.allSongs.count) songs · \(library.playlists.count) playlists")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(EW27Design.primaryText)
                }
                Spacer(minLength: 0)
                Image(systemName: "waveform").font(.system(size: 19, weight: .medium)).foregroundStyle(EW27Design.primaryText.opacity(0.4))
            }
            .padding(16)
            .liquidGlass()
            .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    private var librarySpotlightSection: some View {
        Section {
            HStack(spacing: 13) {
                ZStack {
                    Circle().fill(.cyan.opacity(0.14))
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.cyan)
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text("LOCAL-FIRST LISTENING")
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(.cyan)
                    Text("Your music stays close and ready.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(EW27Design.primaryText.opacity(0.9))
                    Text("Search, queue, and play without leaving your library.")
                        .font(.caption)
                        .foregroundStyle(EW27Design.primaryText.opacity(0.48))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(15)
            .ew27Card()
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    private var studioHeaderSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.cyan)
                        .frame(width: 52, height: 52)
                        .glassRow(radius: 16)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SOUND STUDIO").font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(.cyan)
                        Text(player.selectedPreset.rawValue)
                            .font(.title3.weight(.bold)).foregroundStyle(EW27Design.primaryText)
                        Text(player.eqEnabled ? "EQ active · \(player.reverbMode) space" : "EQ bypassed · \(player.reverbMode) space")
                            .font(.caption).foregroundStyle(EW27Design.primaryText.opacity(0.50)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Circle().fill(player.eqEnabled ? Color.green : EW27Design.primaryText.opacity(0.30)).frame(width: 8, height: 8)
                }
                HStack(spacing: 8) {
                    studioFact(icon: "airplay.audio", text: player.routeName)
                    studioFact(icon: "waveform", text: player.audioQualityLabel)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .liquidGlass()
            .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    private var studioToolsSummary: some View {
        HStack(spacing: 8) {
            studioMetric(icon: "waveform.path.ecg", title: "EQ", value: player.eqEnabled ? "Active" : "Flat")
            studioMetric(icon: "square.stack.3d.up", title: "Space", value: player.reverbMode)
            studioMetric(icon: "arrow.left.arrow.right", title: "Fade", value: player.crossfadeSeconds > 0 ? "\(Int(player.crossfadeSeconds))s" : "Off")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .liquidGlass()
    }

    private func studioMetric(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(.cyan)
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(EW27Design.primaryText.opacity(0.42))
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(EW27Design.primaryText.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func studioFact(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(EW27Design.primaryText.opacity(0.52))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .glassChip()
    }

    /// A restrained tint borrowed from the current artwork, so glass surfaces
    /// pick up the album's colour the way Apple Music's do.
    private var artworkGlassTint: Color? {
        guard let tint = player.artworkTint else { return nil }
        return Color(uiColor: tint).opacity(0.28)
    }

    /// The lyric line currently being sung, mirroring the lyrics reader's
    /// clock and sync offset.
    private func miniSubtitle(at date: Date) -> String {
        let fallback = player.currentItem?.artist ?? "EW27 Player"
        guard let lyrics = player.lyricsStore.lyrics, lyrics.isSynced else { return fallback }
        let time = player.lyricPlaybackTime(at: date) + player.lyricsStore.syncOffset
        var current: String?
        for line in lyrics.lines {
            if line.start <= time { current = line.plainText } else { break }
        }
        guard let current, !current.isEmpty else { return fallback }
        return current
    }

    private var miniPlayer: some View {
        HStack(spacing: 12) {
            Group {
                if let artwork = ArtworkCache.shared.image(for: player.currentItem?.persistentID ?? 0, artwork: player.currentItem?.artwork, size: CGSize(width: 96, height: 96)) {
                    Image(uiImage: artwork).resizable().scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(colors: [.cyan.opacity(0.8), .blue.opacity(0.55), .purple.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "waveform").font(.system(size: 18, weight: .semibold)).foregroundStyle(EW27Design.primaryText)
                    }
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .matchedGeometryEffect(id: "player-artwork", in: playerNamespace)

            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentItem?.title ?? "No track selected")
                    .font(EW27Type.row)
                    .lineLimit(1)
                // Shows the line being sung right now when lyrics are synced;
                // falls back to the artist otherwise.
                TimelineView(.periodic(from: .now, by: 0.4)) { timeline in
                    Text(miniSubtitle(at: timeline.date))
                        .font(EW27Type.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                        .animation(reduceMotion ? nil : Motion.crossfade, value: miniSubtitle(at: timeline.date))
                }
                if let remaining = player.sleepRemaining {
                    Text(String(format: "Sleep %.0fs", remaining)).font(.caption2).foregroundStyle(.cyan)
                }
            }
            Spacer(minLength: 4)
            Button { haptic(); player.togglePlayPause() } label: {
                EW27PlayPauseIcon(isPlaying: player.isPlaying, size: 14)
                    .foregroundStyle(EW27Design.primaryText)
                    .frame(width: 38, height: 38)
                    .glassCircle(tint: EW27Design.cyan.opacity(0.30))
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            .buttonStyle(MusicPressStyle())
            Button { haptic(); player.nextTrack() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 38)
            }
            .accessibilityLabel("Next track")
            .buttonStyle(MusicPressStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlass(prominent: true, tint: artworkGlassTint, interactive: true, translucent: true)
        .overlay(alignment: .bottom) {
            MiniProgressLine(clock: player.clock)
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture { selectedTab = .player; setLyricsVisible(false) }
    }

    private var playerSection: some View {
        GeometryReader { proxy in
            if player.currentItem == nil {
                coldStartState
                    .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                // Apple Music proportions: header, large cover, then the controls
                // docked in the lower third over the artwork's own blur.
                let coverSide = max(190, min(proxy.size.width - 44, proxy.size.height * 0.46))
                ZStack {
                    playerBackdrop(size: proxy.size)

                    VStack(spacing: 0) {
                        deckHeader
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                        Spacer(minLength: 10)
                        coverView(side: coverSide)
                        Spacer(minLength: 10)
                        VStack(spacing: 12) {
                            deckIdentity
                            playerSignalChips
                            deckProgress
                            deckTransport
                                .padding(.top, 2)
                            deckActionRow
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .environment(\.colorScheme, .dark)
            }
        }
        .ignoresSafeArea(edges: .horizontal)
    }

    /// The artwork itself, blurred, filling the whole player. No flat base colour
    /// underneath, so the screen never shows an empty black band.
    private func playerBackdrop(size: CGSize) -> some View {
        ZStack {
            Color.black
            if let artwork = player.currentArtwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .blur(radius: 64)
                    .scaleEffect(1.35)
                    .opacity(0.95)
                    .clipped()
            }
            LinearGradient(
                colors: [.black.opacity(0.45), .black.opacity(0.12), .black.opacity(0.30), .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .drawingGroup()
    }

    /// The cover keeps its true aspect ratio, inside a square frame.
    private func coverView(side: CGFloat) -> some View {
        Group {
            if vinylMode {
                VinylView(image: player.currentArtwork, isPlaying: player.isPlaying, speed: player.speed)
            } else if let artwork = player.currentArtwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.42), radius: 30, y: 14)
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 46, weight: .light))
                            .foregroundStyle(.white.opacity(0.45))
                    }
            }
        }
        .frame(width: side, height: side)
        .drawingGroup()
        .scaleEffect(!reduceMotion && player.isPlaying && albumArtMotion ? 1.012 : 1)
        .id(player.currentItem?.persistentID)
        .transition(.opacity)
        .animation(reduceMotion ? nil : Motion.crossfade, value: player.currentItem?.persistentID)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard let item = player.currentItem else { return }
            haptic()
            favorites.toggle(item)
        }
        .gesture(
            DragGesture(minimumDistance: 28)
                .onEnded { value in
                    guard abs(value.translation.width) > 62,
                          abs(value.translation.width) > abs(value.translation.height) else { return }
                    haptic()
                    if value.translation.width < 0 { player.nextTrack() } else { player.previousTrack() }
                }
        )
        .accessibilityHint("Swipe left or right to change tracks. Double tap to favorite.")
    }

    private var coldStartState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(.cyan.opacity(0.12))
                    .frame(width: 118, height: 118)
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(.cyan)
            }
            VStack(spacing: 7) {
                Text("Your listening space")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Choose a local track to start your session.")
                    .font(.subheadline)
                    .foregroundStyle(EW27Design.primaryText.opacity(0.58))
                    .multilineTextAlignment(.center)
            }
            Button {
                haptic()
                withAnimation(reduceMotion ? nil : Motion.transition) { selectedTab = .library }
            } label: {
                Label("Browse library", systemImage: "music.note.list")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .frame(height: 46)
                    .background(Color.cyan, in: Capsule())
            }
            .buttonStyle(MusicPressStyle())
            .accessibilityHint("Open your local music library")
        }
        .padding(28)
        .frame(maxWidth: 340)
        .liquidGlass(prominent: true)
    }

    private var deckHeader: some View {
        HStack(spacing: 10) {
            Text("NOW PLAYING")
                .font(.caption2.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(EW27Design.primaryText.opacity(0.64))
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Image(systemName: "airplay.audio").font(.caption2)
                Text(player.routeName).font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.75)
            }
            .foregroundStyle(EW27Design.primaryText.opacity(0.64))
            Menu {
                Toggle("Vinyl artwork", isOn: $vinylMode)
                Toggle("Keep pitch", isOn: Binding(get: { player.keepPitch }, set: { player.keepPitch = $0; player.setSpeed(player.speed) }))
                Button {
                    showPlaybackSettings = true
                } label: {
                    Label("Playback settings", systemImage: "slider.horizontal.3")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(EW27Design.primaryText.opacity(0.85))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Playback options")
        }
    }

    private var playerSignalChips: some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 7) {
                signalChip(icon: "waveform", text: player.selectedPreset.rawValue)
                signalChip(icon: "speedometer", text: String(format: "%.2fx", player.speed))
                if player.lyricsStore.lyrics != nil {
                    signalChip(icon: "quote.bubble.fill", text: "Lyrics")
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 1)
    }

    private func signalChip(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(EW27Type.chip)
            .foregroundStyle(EW27Design.primaryText.opacity(0.62))
            .padding(.horizontal, 9)
            .frame(height: 26)
            .glassChip()
    }


    private var deckIdentity: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(player.currentItem?.title ?? "Nothing playing")
                    .font(EW27Type.hero)
                    .foregroundStyle(EW27Design.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(player.currentItem?.artist ?? "Choose a track in your library")
                    .font(EW27Type.body)
                    .foregroundStyle(EW27Design.primaryText.opacity(0.60))
                    .lineLimit(1)
                Text(player.audioQualityLabel)
                    .font(EW27Type.caption.weight(.medium))
                    .foregroundStyle(EW27Design.primaryText.opacity(0.40))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let item = player.currentItem {
                let isFavorite = favorites.contains(item)
                Button { favorites.toggle(item) } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(isFavorite ? Color.yellow : EW27Design.primaryText.opacity(0.72))
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(EW27TransportPressStyle())
                .accessibilityLabel(isFavorite ? "Remove Favorite" : "Add to Favorites")
            }
        }
        .padding(.horizontal, 2)
    }

    private var deckProgress: some View {
        VStack(spacing: 10) {
            SlimPlaybackProgressBar(clock: player.clock) { player.seek(to: $0) }
                .frame(height: 20)
            PlaybackTimeLabels(clock: player.clock)
        }
        .padding(.horizontal, 2)
    }

    /// Bottom action row, mirroring Apple Music's lyrics / queue / shuffle strip.
    private var deckActionRow: some View {
        HStack(spacing: 0) {
            actionButton("quote.bubble", label: "Lyrics", active: showLyrics) {
                setLyricsVisible(true)
            }
            .disabled(player.currentItem == nil)
            Spacer(minLength: 0)
            actionButton("list.bullet", label: "Queue", active: false) {
                showQueue = true
            }
            Spacer(minLength: 0)
            actionButton("shuffle", label: "Shuffle", active: player.shuffleEnabled) {
                player.shuffleEnabled.toggle()
            }
        }
        .padding(.horizontal, 30)
    }

    private func actionButton(_ symbol: String, label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(active ? EW27Design.cyan : EW27Design.primaryText.opacity(0.78))
                .frame(width: 48, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(EW27TransportPressStyle())
        .accessibilityLabel(label)
    }

    private var deckTransport: some View {
        HStack(spacing: 44) {
            transportButton("backward.fill", label: "Previous track", size: 30) {
                haptic()
                player.previousTrack()
            }
            Button { haptic(); player.togglePlayPause() } label: {
                EW27PlayPauseIcon(isPlaying: player.isPlaying, size: 42)
                    .foregroundStyle(EW27Design.primaryText)
                    .frame(width: 64, height: 64)
                    .contentShape(Rectangle())
            }
            .buttonStyle(EW27TransportPressStyle())
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            transportButton("forward.fill", label: "Next track", size: 30) {
                haptic()
                player.nextTrack()
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Plain glyph button with a generous, predictable hit area.
    private func transportButton(_ symbol: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(EW27Design.primaryText)
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(EW27TransportPressStyle())
        .accessibilityLabel(label)
    }

    private var deckShortcuts: some View {
        HStack {
            deckActionButton("Shuffle", icon: "shuffle", isActive: player.shuffleEnabled) { player.shuffleEnabled.toggle() }
            Spacer()
            deckActionButton("Lyrics", icon: "quote.bubble.fill", isActive: showLyrics) {
                setLyricsVisible(true)
            }
                .disabled(player.currentItem == nil)
            Spacer()
            deckActionButton("Queue", icon: "list.bullet", isActive: false) { showQueue = true }
        }
    }

    private var deckTuning: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ForEach(speedPresets, id: \.self) { value in
                        Button(String(format: "%g×", value)) { player.setSpeed(value) }
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(abs(player.speed - value) < 0.02 ? Color.black : EW27Design.primaryText.opacity(0.76))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .glassChip(isSelected: abs(player.speed - value) < 0.02)
                    }
                }
                PlaybackControlsView(player: player, clock: player.clock, speedState: player.speedState, spectrum: player.spectrumModel, waveform: player.waveformStore)
            }
            .padding(.top, 12)
        } label: {
            HStack {
                Label("Playback settings", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(EW27Design.primaryText.opacity(0.78))
                Spacer()
                Text(String(format: "%.2f×", player.speed))
                    .font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(.cyan)
            }
        }
        .tint(.cyan)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .liquidGlass()
    }

    private func deckActionButton(_ title: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isActive ? Color.cyan : EW27Design.primaryText.opacity(0.62))
                Text(title).font(.caption2.weight(.medium)).foregroundStyle(EW27Design.primaryText.opacity(0.58))
            }
            .frame(width: 68, height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(MusicPressStyle())
    }

    private func playerActionButton(_ symbol: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(EW27Design.primaryText)
                .frame(width: 54, height: 54)
                .glassCircle()
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

                Divider().overlay(EW27Design.primaryText.opacity(0.08))

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
            .ew27Card(prominent: true)
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 12, trailing: 12))
            .listRowBackground(Color.clear)
        } header: {
            EW27SectionLabel("Equalizer", systemImage: "waveform.path.ecg")
        }
    }

    private var allSongsSection: some View {
        Section("All Songs") {
            if library.allSongs.isEmpty {
                EW27EmptyState(
                    systemImage: library.authorization == .authorized ? "music.note.list" : "lock.open",
                    title: library.authorization == .authorized ? (searchText.isEmpty ? "Your library is empty" : "No matching songs") : "Music access is needed",
                    detail: library.message ?? (searchText.isEmpty ? "Add music to your device, then return here to play it." : "Try a different search or clear the filters.")
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
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
                EW27EmptyState(
                    systemImage: "music.note.list",
                    title: "No playlists yet",
                    detail: "Create a playlist in Apple Music and it will appear here."
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
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
                                .foregroundStyle(EW27Design.primaryText.opacity(0.9))
                        }
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(EW27Design.primaryText.opacity(0.08), lineWidth: 1))
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
            .glassRow(isSelected: isCurrent, radius: 16)
        }
        .buttonStyle(MusicPressStyle())
        .listRowInsets(EdgeInsets(top: 3, leading: 14, bottom: 3, trailing: 14))
        .listRowBackground(Color.clear)
        .disabled(item.assetURL == nil)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                haptic()
                player.addToQueue(item, playNext: true)
            } label: {
                Label("Play Next", systemImage: "text.insert")
            }
            .tint(.cyan)
            Button {
                haptic()
                favorites.toggle(item)
            } label: {
                Label(favorites.contains(item) ? "Unfavorite" : "Favorite", systemImage: favorites.contains(item) ? "heart.slash" : "heart")
            }
            .tint(.pink)
        }
        .contextMenu {
            Button { player.addToQueue(item, playNext: true) } label: { Label("Play Next", systemImage: "text.insert") }
            Button { player.addToQueue(item) } label: { Label("Add to Queue", systemImage: "text.append") }
            Button { haptic(); favorites.toggle(item) } label: { Label(favorites.contains(item) ? "Remove Favorite" : "Favorite", systemImage: favorites.contains(item) ? "heart.slash" : "heart") }
        }
        .accessibilityLabel("\(item.title ?? "Untitled"), \(item.artist ?? "Unknown artist")")
        .accessibilityHint(item.assetURL == nil ? "Unavailable on this device" : "Double tap to play. Swipe for queue actions.")
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
        guard UserDefaults.standard.object(forKey: "ew27.haptics.enabled") as? Bool ?? true else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

private struct SlimPlaybackProgressBar: View {
    @ObservedObject var clock: PlaybackClock
    let onSeek: (TimeInterval) -> Void
    @State private var scrubFraction: Double?

    var body: some View {
        GeometryReader { geometry in
            let current = clock.duration > 0 ? clock.elapsed / clock.duration : 0
            let progress = min(1, max(0, scrubFraction ?? current))
            let width = max(0, geometry.size.width)

            let knob: CGFloat = scrubFraction == nil ? 11 : 15
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.30))
                    .frame(height: 6)
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [EW27Design.cyan, .white.opacity(0.92)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * CGFloat(progress), height: 6)
                Circle()
                    .fill(.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.28), radius: 4, y: 1)
                    .offset(x: max(0, width * CGFloat(progress) - knob / 2))
                    .animation(Motion.drag, value: scrubFraction == nil)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        scrubFraction = min(1, max(0, value.location.x / max(1, width)))
                    }
                    .onEnded { value in
                        let target = min(1, max(0, value.location.x / max(1, width)))
                        onSeek(target * clock.duration)
                        scrubFraction = nil
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Playback progress")
            .accessibilityValue(String(format: "%.0f percent", progress * 100))
        }
    }
}
