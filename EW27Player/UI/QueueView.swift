import SwiftUI
import MediaPlayer

struct QueueView: View {
    @StateObject private var model: QueueViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(player: AudioPlayer) {
        _model = StateObject(wrappedValue: QueueViewModel(player: player))
    }

    var body: some View {
        NavigationStack {
            List {
                queueHeader

                if model.items.isEmpty {
                    emptyQueueRow
                } else {
                    ForEach(model.items, id: \.persistentID) { item in
                        if let index = model.items.firstIndex(where: { $0.persistentID == item.persistentID }) {
                            QueueRow(
                                item: item,
                                index: index,
                                isCurrent: index == model.currentIndex,
                                reduceMotion: reduceMotion,
                                onPlay: { model.play(at: index) }
                            )
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    model.remove(at: IndexSet(integer: index))
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .onDelete { model.remove(at: $0) }
                    .onMove { model.move(from: $0, to: $1) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background { ArtworkAuroraBackground(image: model.currentArtwork, tint: model.artworkTint) }
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .buttonStyle(MusicPressStyle())
                        .accessibilityLabel("Close queue")
                }
                if !model.items.isEmpty {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if model.items.count > model.currentIndex + 1 {
                            Button {
                                model.clearUpcoming()
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .accessibilityLabel("Clear upcoming tracks")
                            .accessibilityHint("Keeps the currently playing track")
                        }
                        EditButton()
                    }
                }
            }
            .transaction { transaction in
                // Avoid animating every queue row when playback state changes.
                transaction.animation = nil
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
    }

    private var queueHeader: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PLAYING NEXT")
                            .font(.caption2.weight(.bold))
                            .tracking(1.5)
                            .foregroundStyle(.cyan)
                        Text("\(max(0, model.items.count - model.currentIndex - 1)) tracks up next")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    Spacer()
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.cyan)
                }

                if let current = model.currentItem {
                    HStack(spacing: 12) {
                        QueueArtworkView(item: current, size: 52)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("NOW PLAYING")
                                .font(.caption2.weight(.bold))
                                .tracking(1.2)
                                .foregroundStyle(.white.opacity(0.45))
                            Text(current.title ?? "Untitled")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(current.artist ?? "")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.52))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                            Image(systemName: "waveform")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.cyan)
                                .accessibilityHidden(true)
                        }
                        if !model.items.isEmpty {
                            HStack(spacing: 7) {
                                Image(systemName: "arrow.down.right")
                                    .font(.caption2.weight(.bold))
                                Text("Tap to play now · drag to shape what comes next")
                                    .font(.caption2.weight(.medium))
                            }
                            .foregroundStyle(.white.opacity(0.42))
                        }
                    }
                }
            .padding(16)
            .ew27Card(prominent: true)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    private var emptyQueueRow: some View {
        EW27EmptyState(
            systemImage: "text.line.first.and.arrowtriangle.forward",
            title: "Queue is empty",
            detail: "Choose a song from your library to start playback."
        )
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        .listRowBackground(Color.clear)
    }
}

private struct QueueRow: View {
    let item: MPMediaItem
    let index: Int
    let isCurrent: Bool
    let reduceMotion: Bool
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                Text(String(format: "%02d", index + 1))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(isCurrent ? .cyan : .white.opacity(0.35))
                    .frame(width: 28, alignment: .leading)

                QueueArtworkView(item: item, size: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title ?? "Untitled")
                        .font(.subheadline.weight(isCurrent ? .semibold : .medium))
                        .foregroundStyle(isCurrent ? .cyan : .white)
                        .lineLimit(1)
                    Text(item.artist ?? "")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
                if isCurrent {
                    Image(systemName: "waveform")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.cyan)
                        .accessibilityLabel("Currently playing")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(isCurrent ? Color.cyan.opacity(0.10) : Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isCurrent ? Color.cyan.opacity(0.28) : Color.white.opacity(0.07), lineWidth: 1)
            }
        }
        .buttonStyle(MusicPressStyle())
        .animation(reduceMotion ? nil : Motion.snappy, value: isCurrent)
        .accessibilityLabel("\(item.title ?? "Untitled"), \(item.artist ?? "Unknown artist")")
        .accessibilityHint(isCurrent ? "Currently playing" : "Play this track")
    }
}

private struct QueueArtworkView: View {
    let item: MPMediaItem
    let size: CGFloat
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [.cyan.opacity(0.52), .blue.opacity(0.38), .purple.opacity(0.46)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.34, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).stroke(.white.opacity(0.11), lineWidth: 1))
        .task(id: item.persistentID) {
            let target = CGSize(width: size * 2, height: size * 2)
            image = ArtworkCache.shared.image(for: item.persistentID, artwork: item.artwork, size: target)
        }
        .accessibilityHidden(true)
    }
}
