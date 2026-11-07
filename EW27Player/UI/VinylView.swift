import SwiftUI
import UIKit

final class VinylClock {
    var angle: Double = 0
    var angularVelocity: Double = 0
    private var lastDate: Date?

    func advance(to date: Date, target: Double) {
        guard let previousDate = lastDate else {
            lastDate = date
            return
        }
        let dt = min(0.1, max(0, date.timeIntervalSince(previousDate)))
        lastDate = date
        guard dt > 0 else { return }
        let duration = target > angularVelocity ? 0.6 : 1.2
        angularVelocity += (target - angularVelocity) * min(1, dt / duration)
        angle += angularVelocity * dt
    }
}

struct VinylView: View {
    let image: UIImage?
    let isPlaying: Bool
    let speed: Float
    @State private var clock: VinylClock

    init(image: UIImage?, isPlaying: Bool, speed: Float) {
        self.image = image
        self.isPlaying = isPlaying
        self.speed = speed
        _clock = State(initialValue: VinylClock())
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying && clock.angularVelocity < 0.5)) { timeline in
            Canvas { context, size in
                clock.advance(to: timeline.date, target: isPlaying ? 200 * Double(speed) : 0)

                let diameter = min(size.width, size.height)
                let radius = diameter / 2
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let discRect = CGRect(x: center.x - radius, y: center.y - radius, width: diameter, height: diameter)
                let localDiscRect = CGRect(x: -radius, y: -radius, width: diameter, height: diameter)

                var spinning = context
                spinning.translateBy(x: center.x, y: center.y)
                spinning.rotate(by: .degrees(clock.angle))
                spinning.fill(
                    Path(ellipseIn: localDiscRect),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: Color(white: 0.24), location: 0),
                            .init(color: Color(white: 0.08), location: 0.42),
                            .init(color: .black, location: 1)
                        ]),
                        center: .zero,
                        startRadius: diameter * 0.04,
                        endRadius: radius
                    )
                )

                for index in 1...38 {
                    let grooveRadius = diameter * 0.225 + CGFloat(index) * diameter * 0.0062
                    let grooveRect = CGRect(x: -grooveRadius, y: -grooveRadius, width: grooveRadius * 2, height: grooveRadius * 2)
                    let opacity = index.isMultiple(of: 5) ? 0.16 : 0.055
                    spinning.stroke(
                        Path(ellipseIn: grooveRect),
                        with: .color(.white.opacity(opacity)),
                        lineWidth: index.isMultiple(of: 5) ? 0.8 : 0.45
                    )
                }

                let scratches: [(CGFloat, Double, Double)] = [
                    (0.31, 18, 76),
                    (0.385, 202, 239),
                    (0.445, 116, 147)
                ]
                for scratch in scratches {
                    var path = Path()
                    path.addArc(
                        center: .zero,
                        radius: diameter * scratch.0,
                        startAngle: .degrees(scratch.1),
                        endAngle: .degrees(scratch.2),
                        clockwise: false
                    )
                    spinning.stroke(path, with: .color(.white.opacity(0.20)), lineWidth: 0.45)
                }

                let dustRadius = diameter * 0.004
                let dustPositions = [
                    CGPoint(x: -diameter * 0.34, y: -diameter * 0.16),
                    CGPoint(x: diameter * 0.36, y: diameter * 0.12),
                    CGPoint(x: -diameter * 0.41, y: diameter * 0.29)
                ]
                for point in dustPositions {
                    let speck = CGRect(x: point.x, y: point.y, width: dustRadius * 2, height: dustRadius * 2)
                    spinning.fill(Path(ellipseIn: speck), with: .color(.white.opacity(0.36)))
                }

                let labelDiameter = diameter * 0.4
                let labelRect = CGRect(x: -labelDiameter / 2, y: -labelDiameter / 2, width: labelDiameter, height: labelDiameter)
                if let image {
                    var labelLayer = spinning
                    labelLayer.clip(to: Path(ellipseIn: labelRect))
                    labelLayer.draw(labelLayer.resolve(Image(uiImage: image)), in: labelRect)
                } else {
                    spinning.fill(Path(ellipseIn: labelRect), with: .color(Color(red: 0.08, green: 0.42, blue: 0.58)))
                }
                spinning.stroke(Path(ellipseIn: labelRect), with: .color(.white.opacity(0.74)), lineWidth: max(0.8, diameter * 0.004))

                let notchWidth = diameter * 0.018
                let notchHeight = diameter * 0.052
                let notchRect = CGRect(x: -notchWidth / 2, y: -labelDiameter / 2 + notchHeight * 0.12, width: notchWidth, height: notchHeight)
                spinning.fill(Path(roundedRect: notchRect, cornerSize: CGSize(width: notchWidth / 2, height: notchWidth / 2)), with: .color(.white.opacity(0.96)))

                let sheen = Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.02), location: 0.035),
                    .init(color: .white.opacity(0.12), location: 0.10),
                    .init(color: .white.opacity(0.025), location: 0.17),
                    .init(color: .clear, location: 0.22),
                    .init(color: .clear, location: 0.50),
                    .init(color: .white.opacity(0.02), location: 0.535),
                    .init(color: .white.opacity(0.12), location: 0.60),
                    .init(color: .white.opacity(0.025), location: 0.68),
                    .init(color: .clear, location: 0.73),
                    .init(color: .clear, location: 1)
                ])
                context.fill(
                    Path(ellipseIn: discRect),
                    with: .style(AngularGradient(gradient: sheen, center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)))
                )
                context.fill(
                    Path(ellipseIn: discRect),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: .clear, location: 0.48),
                            .init(color: .black.opacity(0.12), location: 0.78),
                            .init(color: .black.opacity(0.42), location: 1)
                        ]),
                        center: center,
                        startRadius: diameter * 0.2,
                        endRadius: radius
                    )
                )

                let spindleRadius = max(1.6, diameter * 0.014)
                let spindle = CGRect(x: center.x - spindleRadius, y: center.y - spindleRadius, width: spindleRadius * 2, height: spindleRadius * 2)
                context.fill(Path(ellipseIn: spindle), with: .color(.white.opacity(0.9)))
                let spindleCoreRadius = max(0.7, spindleRadius * 0.35)
                let spindleCore = CGRect(x: center.x - spindleCoreRadius, y: center.y - spindleCoreRadius, width: spindleCoreRadius * 2, height: spindleCoreRadius * 2)
                context.fill(Path(ellipseIn: spindleCore), with: .color(.black.opacity(0.82)))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
