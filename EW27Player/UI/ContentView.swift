import SwiftUI
import MediaPlayer
import UIKit

struct ContentView: View {
    @EnvironmentObject private var library: MediaLibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false

    private let speedPresets: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    var body: some View {
        NavigationStack {
            List {
                playerSection
                eqSection
                AudioEffectsSection(player: player)
                allSongsSection
                playlistsSection
            }
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
            .navigationTitle("EW27 Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color(red: 0.035, green: 0.055, blue: 0.12), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") { Task { await library.requestAccessAndLoad() } }
                }
            }
        }
        .overlay(alignment: .top) { RouteAccessoryCard(routeName: player.routeName) }
        .onChange(of: player.elapsed) { _, value in
            if !isScrubbing { scrubValue = value }
        }
        .preferredColorScheme(.dark)
    }

    private var playerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 16) {
                    Group {
                        if let artwork = player.currentItem?.artwork?.image(at: CGSize(width: 240, height: 240)) {
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
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))
                    .shadow(color: .black.opacity(0.28), radius: 12, y: 7)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(player.currentItem?.title ?? "No track selected")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .lineLimit(2)
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
                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 25, weight: .bold))
                            .offset(x: player.isPlaying ? 0 : 2)
                            .frame(width: 72, height: 72)
                            .background(Circle().fill(LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing)))
                            .foregroundStyle(Color(red: 0.02, green: 0.08, blue: 0.16))
                            .shadow(color: .cyan.opacity(0.28), radius: 14, y: 5)
                    }
                    Spacer()
                    Button { player.nextTrack() } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(.white.opacity(0.09)))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)

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
                            Button(String(format: "%g×", value)) { player.setSpeed(value) }
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
                    Toggle("Keep pitch", isOn: $player.keepPitch)
                        .onChange(of: player.keepPitch) { _, _ in player.setSpeed(player.speed) }
                    Toggle("Shuffle", isOn: $player.shuffleEnabled)
                }
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
        Section("Equalizer") {
            Picker("Preset", selection: Binding(get: { player.selectedPreset }, set: { player.applyPreset($0) })) {
                ForEach(AudioPlayer.Preset.allCases) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .pickerStyle(.menu)

            eqSlider(index: 0, title: "60 Hz")
            eqSlider(index: 1, title: "250 Hz")
            eqSlider(index: 2, title: "1 kHz")
            eqSlider(index: 3, title: "4 kHz")
            eqSlider(index: 4, title: "12 kHz")
            eqSlider(title: "Preamp", value: Binding(get: { player.preamp }, set: { player.setPreamp($0) }))

            Button("Reset to Flat") { player.resetEQ() }
                .buttonStyle(.bordered)
        }
    }

    private var allSongsSection: some View {
        Section("All Local Songs") {
            if library.allSongs.isEmpty {
                Text(library.message ?? "No local songs.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(library.allSongs, id: \.persistentID) { item in
                    trackRow(item, queue: library.playableItems(library.allSongs))
                }
            }
        }
    }

    private var playlistsSection: some View {
        Section("Playlists") {
            if library.playlists.isEmpty {
                Text("No local playlists, or permission not granted.")
                    .foregroundStyle(.secondary)
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
        Button {
            if item.assetURL != nil { player.play(item, queue: queue) }
        } label: {
            HStack {
                Image(systemName: player.currentItem?.persistentID == item.persistentID ? "waveform" : "music.note")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(player.currentItem?.persistentID == item.persistentID ? .cyan : .white.opacity(0.68))
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.07)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title ?? "Untitled")
                        .font(.subheadline.weight(.medium))
                    Text(item.artist ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if item.assetURL == nil {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                } else if player.currentItem?.persistentID == item.persistentID {
                    Image(systemName: "speaker.wave.2.fill")
                }
            }
        }
        .disabled(item.assetURL == nil)
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
}
