import SwiftUI
import MediaPlayer

struct QueueView: View {
    @ObservedObject var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("PLAYING NEXT").font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(.cyan)
                                Text("\(player.queue.count) tracks in your queue")
                                    .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.58))
                            }
                            Spacer()
                            Image(systemName: "text.line.first.and.arrowtriangle.forward")
                                .font(.system(size: 17, weight: .semibold)).foregroundStyle(.cyan)
                        }
                        if let current = player.currentItem {
                            HStack(spacing: 12) {
                                queueArtwork(for: current, size: 52)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("NOW PLAYING").font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(.white.opacity(0.45))
                                    Text(current.title ?? "Untitled").font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                                    Text(current.artist ?? "").font(.caption).foregroundStyle(.white.opacity(0.52)).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "waveform")
                                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.cyan)
                                    .symbolEffect(.pulse, options: .repeating)
                            }
                        }
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(LinearGradient(colors: [.white.opacity(0.23), .white.opacity(0.045)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.20), radius: 18, y: 8)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16))
                    .listRowBackground(Color.clear)
                }
                ForEach(Array(player.queue.enumerated()), id: \.element.persistentID) { index, item in
                    Button { player.jumpToQueue(index: index) } label: {
                        HStack(spacing: 12) {
                            Text(String(format: "%02d", index + 1))
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(index == player.currentIndex ? .cyan : .white.opacity(0.35))
                                .frame(width: 28, alignment: .leading)
                            queueArtwork(for: item, size: 46)
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
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(index == player.currentIndex ? Color.cyan.opacity(0.28) : Color.white.opacity(0.08), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .buttonStyle(MusicPressStyle())
                        .accessibilityLabel("Close queue")
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: player.currentItem?.persistentID)
    }

    @ViewBuilder
    private func queueArtwork(for item: MPMediaItem, size: CGFloat) -> some View {
        Group {
            if let image = ArtworkCache.shared.image(for: item.persistentID, artwork: item.artwork, size: CGSize(width: size * 2, height: size * 2)) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [.cyan.opacity(0.52), .blue.opacity(0.38), .purple.opacity(0.46)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.system(size: size * 0.34, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).stroke(.white.opacity(0.11), lineWidth: 1))
    }
}
