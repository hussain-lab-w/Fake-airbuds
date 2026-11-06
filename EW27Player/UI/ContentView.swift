import SwiftUI
import MediaPlayer

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
            .navigationTitle("EW27 Player")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("تحديث") { Task { await library.requestAccessAndLoad() } }
                }
            }
        }
        .overlay(alignment: .top) { RouteAccessoryCard(routeName: player.routeName) }
        .onChange(of: player.elapsed) { _, value in
            if !isScrubbing { scrubValue = value }
        }
    }

    private var playerSection: some View {
        Section("المشغل") {
            Text(player.currentItem?.title ?? "لم يتم اختيار أغنية")
                .font(.headline)
            Text(player.currentItem?.artist ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button { player.previousTrack() } label: { Image(systemName: "backward.fill") }
                Spacer()
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 38))
                }
                Spacer()
                Button { player.nextTrack() } label: { Image(systemName: "forward.fill") }
            }
            .buttonStyle(.plain)

            Slider(value: $scrubValue, in: 0...max(1, player.duration), onEditingChanged: { editing in
                isScrubbing = editing
                if !editing { player.seek(to: scrubValue) }
            })
            HStack {
                Text(formatTime(isScrubbing ? scrubValue : player.elapsed))
                Spacer()
                Text(formatTime(player.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("السرعة")
                    Spacer()
                    Text(String(format: "%.2fx", player.speed)).font(.caption.monospacedDigit())
                }
                HStack(spacing: 6) {
                    ForEach(speedPresets, id: \.self) { value in
                        Button(String(format: "%g×", value)) { player.setSpeed(value) }
                            .font(.caption2)
                            .buttonStyle(.bordered)
                            .tint(abs(player.speed - value) < 0.02 ? .accentColor : .gray)
                    }
                }
                Slider(value: Binding(get: { Double(player.speed) }, set: { player.setSpeed(Float($0)) }), in: 0.25...4)
            }
            Toggle("Keep pitch / إبقاء النغمة", isOn: $player.keepPitch)
                .onChange(of: player.keepPitch) { _, _ in player.setSpeed(player.speed) }

            Toggle("تشغيل عشوائي", isOn: $player.shuffleEnabled)
            LabeledContent("المسار", value: player.routeName)
            if let message = player.playbackMessage {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            Text("إذا انتهت الأغنية، اضغط تشغيل لإعادة تشغيلها أو استخدم التالي للانتقال.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var eqSection: some View {
        Section("المعادل الصوتي") {
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

            Button("إرجاع Flat") { player.resetEQ() }
                .buttonStyle(.bordered)
        }
    }

    private var allSongsSection: some View {
        Section("كل الأغاني المحلية") {
            if library.allSongs.isEmpty {
                Text(library.message ?? "لا توجد أغاني محلية.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(library.allSongs, id: \.persistentID) { item in
                    trackRow(item, queue: library.playableItems(library.allSongs))
                }
            }
        }
    }

    private var playlistsSection: some View {
        Section("قوائم التشغيل") {
            if library.playlists.isEmpty {
                Text("لا توجد قوائم تشغيل محلية أو لم تُمنح الصلاحية.")
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
                        Text(playlist.value(forProperty: MPMediaPlaylistPropertyName) as? String ?? "قائمة تشغيل")
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title ?? "بدون عنوان")
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
