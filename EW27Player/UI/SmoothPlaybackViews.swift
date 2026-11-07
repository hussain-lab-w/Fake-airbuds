import SwiftUI

struct MiniProgressLine: View {
    @ObservedObject var clock: PlaybackClock

    var body: some View {
        GeometryReader { proxy in
            let progress = clock.duration > 0 ? CGFloat(min(1, max(0, clock.elapsed / clock.duration))) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.10))
                Capsule()
                    .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 2)
    }
}

struct PlaybackControlsView: View {
    @ObservedObject var player: AudioPlayer
    @ObservedObject var clock: PlaybackClock
    @ObservedObject var speedState: SpeedState
    @ObservedObject var spectrum: SpectrumModel
    @State private var speedValue: Double = 1
    @State private var speedDragging = false

    private let presets: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SpectrumView(bars: spectrum.bars)
            WaveformView(store: player.waveformStore, clock: clock) { player.seek(to: $0) }
            HStack {
                Text(formatTime(clock.elapsed))
                Spacer()
                Text(formatTime(clock.duration))
            }
            .font(.caption2.monospacedDigit().weight(.medium))
            .foregroundStyle(.white.opacity(0.58))
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Speed", systemImage: "speedometer").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(String(format: "%.2fx", speedState.displayed))
                        .font(.caption.monospacedDigit().weight(.bold)).foregroundStyle(.cyan)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(presets, id: \.self) { value in
                        Button(String(format: "%g×", value)) { player.setSpeed(value) }
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Capsule().fill(abs(speedState.displayed - value) < 0.02 ? Color.cyan.opacity(0.22) : Color.white.opacity(0.07)))
                            .foregroundStyle(abs(speedState.displayed - value) < 0.02 ? .cyan : .white.opacity(0.8))
                            .buttonStyle(.plain)
                    }
                }
                Slider(value: Binding(get: {
                    speedDragging ? speedValue : Double(speedState.displayed)
                }, set: { speedValue = $0; player.setSpeedWhileDragging(Float($0)) }), in: 0.25...4, onEditingChanged: { editing in
                    speedDragging = editing
                    if editing { speedValue = Double(speedState.displayed) }
                    else { player.setSpeed(Float(speedValue)); UserDefaults.standard.set(Double(speedState.displayed), forKey: "ew27.speed.global.v1") }
                })
                .tint(.cyan)
            }
        }
        .onAppear { speedValue = Double(speedState.displayed) }
    }

    private func formatTime(_ value: TimeInterval) -> String {
        guard value.isFinite else { return "0:00" }
        let total = max(0, Int(value.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
