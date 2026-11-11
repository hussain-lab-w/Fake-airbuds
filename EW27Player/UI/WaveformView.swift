import SwiftUI

struct WaveformView: View {
    @ObservedObject var store: WaveformStore
    @ObservedObject var clock: PlaybackClock
    let onSeek: (TimeInterval) -> Void
    @State private var preview: Double?

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                guard !store.peaks.isEmpty else {
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: size.height / 2))
                    line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    context.stroke(line, with: .color(.white.opacity(0.25)), lineWidth: 1)
                    return
                }
                let count = store.peaks.count
                let gap: CGFloat = 1
                let width = max(1, (size.width - CGFloat(count - 1) * gap) / CGFloat(count))
                let position = preview ?? (clock.duration > 0 ? clock.elapsed / clock.duration : 0)
                for index in 0..<count {
                    let value = CGFloat(store.peaks[index])
                    let height = max(2, value * size.height)
                    let x = CGFloat(index) * (width + gap)
                    let rect = CGRect(x: x, y: (size.height - height) / 2, width: width, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(Double(index) / Double(count) < position ? .cyan : .white.opacity(0.25)))
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let ratio = min(1, max(0, value.location.x / max(1, proxy.size.width)))
                preview = Double(ratio)
            }.onEnded { value in
                let ratio = min(1, max(0, value.location.x / max(1, proxy.size.width)))
                preview = nil
                onSeek(clock.duration * Double(ratio))
            })
        }
        .frame(height: 32)
        .transaction { transaction in transaction.animation = nil }
    }
}
