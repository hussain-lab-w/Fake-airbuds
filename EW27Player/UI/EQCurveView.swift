import SwiftUI

struct EQCurveView: View {
    let frequencies: [Float]
    let gains: [Float]
    let profileName: String?

    var body: some View {
        Canvas { context, size in
            let left: CGFloat = 8
            let right = size.width - 8
            let top: CGFloat = 8
            let bottom = size.height - 8
            var path = Path()
            for index in 0..<max(1, frequencies.count) {
                let frequency = max(20, frequencies[index])
                let x = left + CGFloat((log10(Double(frequency)) - log10(20)) / (log10(20000) - log10(20))) * (right - left)
                let gain = Double(gains.indices.contains(index) ? gains[index] : 0)
                let y = top + CGFloat((15 - max(-15, min(15, gain))) / 30) * (bottom - top)
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(.cyan), lineWidth: 2)
            var zero = Path()
            zero.move(to: CGPoint(x: left, y: size.height / 2))
            zero.addLine(to: CGPoint(x: right, y: size.height / 2))
            context.stroke(zero, with: .color(.white.opacity(0.16)), lineWidth: 1)
        }
        .frame(height: 100)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topLeading) {
            if let profileName { Text("Custom profile: \(profileName)").font(.caption2).foregroundStyle(.cyan).padding(8) }
        }
    }
}
