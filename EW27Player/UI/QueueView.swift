import SwiftUI
import MediaPlayer

struct QueueView: View {
    @ObservedObject var player: AudioPlayer

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "text.line.first.and.arrowtriangle.forward")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(.cyan)
                            .frame(width: 48, height: 48)
                            .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("PLAY QUEUE").font(.caption2.weight(.bold)).tracking(1.4).foregroundStyle(.cyan)
                            Text("\(player.queue.count) tracks · drag to reorder")
                                .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.62))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
                }
                ForEach(Array(player.queue.enumerated()), id: \.element.persistentID) { index, item in
                    Button { player.jumpToQueue(index: index) } label: {
                        HStack(spacing: 12) {
                            Text(String(format: "%02d", index + 1))
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(index == player.currentIndex ? .cyan : .white.opacity(0.35))
                                .frame(width: 28, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title ?? "Untitled")
                                    .font(.subheadline.weight(index == player.currentIndex ? .semibold : .medium))
                                    .foregroundStyle(index == player.currentIndex ? .cyan : .white)
                                    .lineLimit(1)
                                Text(item.artist ?? "").font(.caption).foregroundStyle(.white.opacity(0.48)).lineLimit(1)
                            }
                            Spacer()
                            if index == player.currentIndex {
                                Image(systemName: "waveform")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.cyan)
                                    .symbolEffect(.pulse, options: .repeating)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(index == player.currentIndex ? .cyan.opacity(0.09) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(MusicPressStyle())
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                }
                .onDelete { player.removeFromQueue(at: $0) }
                .onMove { player.moveQueue(from: $0, to: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background { ArtworkAuroraBackground(image: player.currentArtwork, tint: player.artworkTint) }
            .navigationTitle("Up Next")
            .toolbar { EditButton() }
        }
    }
}
