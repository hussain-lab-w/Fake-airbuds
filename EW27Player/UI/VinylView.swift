import SwiftUI
import UIKit

struct VinylView: View {
    let image: UIImage?
    let isPlaying: Bool
    let speed: Float
    @State private var angle: Double = 0
    @State private var angularVelocity: Double = 0
    @State private var lastDate = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let target = isPlaying ? 200 * Double(speed) : 0
            let delta = min(0.1, max(0, timeline.date.timeIntervalSince(lastDate)))
            let nextVelocity = angularVelocity + (target - angularVelocity) * min(1, delta / (target == 0 ? 1.2 : 0.6))
            ZStack {
                Canvas { context, size in
                    let diameter = min(size.width, size.height)
                    let rect = CGRect(x: (size.width - diameter) / 2, y: (size.height - diameter) / 2, width: diameter, height: diameter)
                    context.fill(Path(ellipseIn: rect), with: .color(.black))
                    for index in 1..<18 {
                        let inset = diameter * CGFloat(index) * 0.018
                        context.stroke(Path(ellipseIn: rect.insetBy(dx: inset, dy: inset)), with: .color(.white.opacity(index.isMultiple(of: 3) ? 0.13 : 0.07)), lineWidth: 0.7)
                    }
                    let highlight = Path(ellipseIn: rect.insetBy(dx: diameter * 0.06, dy: diameter * 0.06))
                    context.stroke(highlight, with: .color(.white.opacity(0.10)), lineWidth: diameter * 0.03)
                }
                .rotationEffect(.degrees(angle))
                if let image {
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(width: 42, height: 42)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                } else {
                    Circle().fill(.cyan.opacity(0.7)).frame(width: 42, height: 42)
                }
                Circle().fill(.black).frame(width: 6, height: 6)
            }
            .onAppear { lastDate = timeline.date }
            .onChange(of: timeline.date) { _, date in
                angle += angularVelocity * delta
                angularVelocity = nextVelocity
                lastDate = date
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
