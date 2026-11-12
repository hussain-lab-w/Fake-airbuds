import SwiftUI
import MediaPlayer

struct NowPlayingFullView: View {
    @ObservedObject var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var showLyrics = false
    @State private var showQueue = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Capsule().fill(.white.opacity(0.35)).frame(width: 42, height: 5)
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(.white.opacity(0.09)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close player")
                        Spacer()
                     Text("Now Playing").font(.headline)
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) { showLyrics.toggle() }
                        } label: {
                            Image(systemName: showLyrics ? "photo" : "quote.bubble")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(.white.opacity(0.09)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showLyrics ? "Show artwork" : "Show lyrics")

                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 8)

                if showLyrics {
                    LyricsView(player: player, store: player.lyricsStore)
                    .frame(width: geometry.size.width, height: max(0, geometry.size.height - 69))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            artwork
                            Text(player.currentItem?.title ?? "No track selected")
                                .font(.title2.bold()).multilineTextAlignment(.center)
                            Text(player.currentItem?.artist ?? "").foregroundStyle(.secondary)
                            WaveformView(store: player.waveformStore, clock: player.clock) { player.seek(to: $0) }
                            PlaybackTimeLabels(clock: player.clock)
                                .font(.caption.monospacedDigit())
                            SpectrumView(bars: player.spectrumModel.bars)
                            Text(String(format: "Speed %.2fx", player.speed)).font(.subheadline.weight(.semibold)).foregroundStyle(.cyan)
                            PlayerInspector(player: player) { showQueue = true }
                        }
                        .frame(width: max(0, geometry.size.width - 40), alignment: .top)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                    }
                    .background { background }
                    .clipped()
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: $showQueue) { QueueView(player: player) }
            .background { background }
                .gesture(DragGesture().onEnded { value in
            guard !showLyrics else { return }
            if value.translation.height > 120 {
                dismiss()
            } else if abs(value.translation.width) > 100 {
                value.translation.width < 0 ? player.nextTrack() : player.previousTrack()
            }
        })

        }
    }

    private var background: some View {
        ArtworkAuroraBackground(image: player.currentArtwork, tint: player.artworkTint)
    }

    private var artwork: some View {
        Group {
            if vinylEnabled {
                VinylView(image: player.currentArtwork, isPlaying: player.isPlaying, speed: player.speed)
            } else if let image = player.currentArtwork {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(.white.opacity(0.22), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.42), radius: 24, y: 12)
            } else {
                Image(systemName: "waveform").font(.system(size: 70)).frame(maxWidth: .infinity).frame(height: 280).background(.cyan.opacity(0.15), in: RoundedRectangle(cornerRadius: 28))
            }
        }
        .frame(maxWidth: 330).frame(height: 330)
        .onTapGesture(count: 2) { player.togglePlayPause() }
    }

    private var vinylEnabled: Bool { UserDefaults.standard.bool(forKey: "ew27.vinyl.enabled") }

}
