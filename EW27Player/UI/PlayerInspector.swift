import SwiftUI
import MediaPlayer

struct PlayerInspector: View {
    @ObservedObject var player: AudioPlayer
    let showQueue: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                InspectorPill(icon: "waveform", text: player.audioQualityLabel)
                InspectorPill(icon: "airplay.audio", text: player.routeName)
                if let lyrics = player.lyricsStore.lyrics {
                    InspectorPill(icon: "quote.bubble", text: lyrics.hasWordTiming ? "Word sync" : "Line sync")
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Button(action: showQueue) {
                    Label("Up Next", systemImage: "list.bullet")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.cyan)
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 42, height: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            }
            if player.queue.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Next in queue")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(player.queue.count - 1) tracks")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.cyan)
                    }
                    ForEach(Array(nextItems.prefix(2)), id: \.persistentID) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "music.note")
                                .foregroundStyle(.cyan.opacity(0.8))
                            Text(item.title ?? "Untitled")
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(item.artist ?? "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(12)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
        }
    }

    private var nextItems: [MPMediaItem] {
        guard let current = player.currentItem,
              let index = player.queue.firstIndex(where: { $0.persistentID == current.persistentID }) else { return [] }
        return Array(player.queue.dropFirst(index + 1))
    }
}

private struct InspectorPill: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.78))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.white.opacity(0.08), in: Capsule())
    }
}
