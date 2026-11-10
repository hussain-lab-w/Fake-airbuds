import SwiftUI
import MediaPlayer
import UIKit

struct RebuiltRootView: View {
    @EnvironmentObject private var library: MediaLibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var favorites: FavoritesStore
    @State private var tab: RootTab = .player
    @State private var search = ""
    @State private var favoritesOnly = false
    @State private var showQueue = false
    @State private var showFullPlayer = false
    @State private var vinylEnabled = false

    private enum RootTab: String, CaseIterable {
        case player, library, sound
        var title: String {
            switch self { case .player: return "Player"; case .library: return "Library"; case .sound: return "Sound" }
        }
        var icon: String {
            switch self { case .player: return "waveform"; case .library: return "music.note.list"; case .sound: return "slider.horizontal.3" }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ArtworkAuroraBackground(image: player.currentArtwork, tint: player.artworkTint)
            Group {
                switch tab {
                case .player: playerDashboard
                case .library: libraryDashboard
                case .sound: soundDashboard
                }
            }
            .safeAreaPadding(.bottom, 74)
            bottomBar
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showQueue) { QueueView(player: player) }
        .sheet(isPresented: $showFullPlayer) { NowPlayingFullView(player: player) }
        .overlay(alignment: .top) { RouteAccessoryCard(routeName: player.routeName) }
    }

    private var playerDashboard: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                dashboardHeader
                artworkHero
                trackTitle
                PlaybackControlsView(player: player, clock: player.clock, speedState: player.speedState, spectrum: player.spectrumModel, waveform: player.waveformStore)
                PlayerInspector(player: player) { showQueue = true }
                playerToggles
                if let message = player.playbackMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
    }

    private var dashboardHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("EW27 PLAYER")
                    .font(.caption.weight(.bold))
                    .tracking(2.2)
                    .foregroundStyle(.cyan)
                Text("Now Playing")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
            }
            Spacer()
            Button { showFullPlayer = true } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var artworkHero: some View {
        Group {
            if vinylEnabled {
                VinylView(image: player.currentArtwork, isPlaying: player.isPlaying, speed: player.speed)
            } else if let image = player.currentArtwork {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1) }
            } else {
                ZStack {
                    LinearGradient(colors: [.cyan.opacity(0.8), .blue.opacity(0.45), .purple.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "waveform")
                        .font(.system(size: 68, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
        }
        .frame(maxWidth: 360)
        .aspectRatio(1, contentMode: .fit)
        .shadow(color: .black.opacity(0.38), radius: 26, y: 14)
        .onTapGesture { showFullPlayer = true }
        .contextMenu {
            Toggle("Vinyl mode", isOn: $vinylEnabled)
        }
    }

    private var trackTitle: some View {
        VStack(spacing: 4) {
            Text(player.currentItem?.title ?? "Choose a song")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(player.currentItem?.artist ?? "Your local library")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
        }
    }

    private var playerToggles: some View {
        HStack(spacing: 10) {
            Toggle("Keep pitch", isOn: $player.keepPitch)
                .onChange(of: player.keepPitch) { _, _ in player.setSpeed(player.speed) }
            Toggle("Shuffle", isOn: $player.shuffleEnabled)
        }
        .font(.caption.weight(.semibold))
        .tint(.cyan)
        .padding(.horizontal, 4)
    }

    private var libraryDashboard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Library").font(.system(size: 30, weight: .bold, design: .rounded))
                Spacer()
                Button { Task { await library.requestAccessAndLoad() } } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Title, artist, album", text: $search)
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
            }
            .padding(12)
            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            Toggle("Favorites only", isOn: $favoritesOnly)
                .font(.caption.weight(.semibold))
                .tint(.cyan)
                .padding(.horizontal, 20)
            List {
                Section("All Local Songs") {
                    ForEach(filteredSongs, id: \.persistentID) { item in libraryRow(item) }
                }
                if !library.playlists.isEmpty {
                    Section("Playlists") {
                        ForEach(library.playlists, id: \.persistentID) { playlist in
                            DisclosureGroup(playlist.value(forProperty: MPMediaPlaylistPropertyName) as? String ?? "Playlist") {
                                ForEach(library.items(in: playlist), id: \.persistentID) { item in libraryRow(item) }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    private func libraryRow(_ item: MPMediaItem) -> some View {
        let playable = item.assetURL != nil
        let current = player.currentItem?.persistentID == item.persistentID
        return Button {
            guard playable else { return }
            player.play(item, queue: library.playableItems(filteredSongs))
            tab = .player
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let image = ArtworkCache.shared.image(for: item.persistentID, artwork: item.artwork, size: CGSize(width: 100, height: 100)) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        ZStack { Color.white.opacity(0.08); Image(systemName: current ? "waveform" : "music.note") }
                    }
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title ?? "Untitled").font(.subheadline.weight(current ? .bold : .medium)).foregroundStyle(current ? .cyan : .primary).lineLimit(1)
                    Text(item.artist ?? "Unknown artist").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: playable ? (current ? "waveform" : "play.fill") : "lock.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(current ? .cyan : .secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(!playable)
        .contextMenu {
            if playable {
                Button { player.addToQueue(item, playNext: true) } label: { Label("Play Next", systemImage: "text.insert") }
                Button { favorites.toggle(item) } label: { Label(favorites.contains(item) ? "Remove Favorite" : "Favorite", systemImage: "heart") }
            }
        }
    }

    private var soundDashboard: some View {
        List {
            Section {
                EQConsole(player: player)
            }
            AudioEffectsSection(player: player)
            SettingsSection(player: player)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .overlay(alignment: .topLeading) {
            Text("Sound").font(.system(size: 30, weight: .bold, design: .rounded)).padding(.leading, 18).padding(.top, 12)
        }
        .safeAreaInset(edge: .top) { Color.clear.frame(height: 50) }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(RootTab.allCases, id: \.self) { item in
                Button { withAnimation(.easeInOut(duration: 0.22)) { tab = item } } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon).font(.system(size: 18, weight: .semibold))
                        Text(item.title).font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(tab == item ? .cyan : .white.opacity(0.54))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(tab == item ? .cyan.opacity(0.12) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }
    }

    private var filteredSongs: [MPMediaItem] {
        library.allSongs.filter { item in
            let fields = [item.title, item.artist, item.albumTitle].compactMap { $0 }
            let matches = search.isEmpty || fields.contains { $0.localizedCaseInsensitiveContains(search) }
            return matches && (!favoritesOnly || favorites.contains(item))
        }
    }
}

private struct EQConsole: View {
    @ObservedObject var player: AudioPlayer
    private let titles = ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label("Equalizer", systemImage: "waveform.path.ecg")
                    .font(.headline.weight(.bold))
                Spacer()
                Toggle("EQ", isOn: Binding(get: { player.eqEnabled }, set: player.setEQEnabled))
                    .labelsHidden()
                    .tint(.cyan)
            }
            EQCurveView(frequencies: [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000], gains: player.eqGains, profileName: player.activeEQProfileName)
            ForEach(titles.indices, id: \.self) { index in
                EQSliderControl(player: player, index: index, title: "\(titles[index]) Hz")
            }
            EQSliderControl(player: player, index: nil, title: "Preamp")
            HStack {
                Picker("Preset", selection: Binding(get: { player.selectedPreset }, set: player.applyPreset)) {
                    ForEach(AudioPlayer.Preset.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                Spacer()
                Button("Reset") { player.resetEQ() }.buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 8)
    }
}
