import SwiftUI

struct SpectrumView: View {
    let bars: [Float]

    var body: some View {
        Canvas { context, size in
            let count = max(1, bars.count)
            let spacing: CGFloat = 2
            let width = max(1, (size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            for (index, value) in bars.enumerated() {
                let height = max(3, CGFloat(max(0, min(1, value))) * (size.height - 4))
                let rect = CGRect(x: CGFloat(index) * (width + spacing), y: size.height - height, width: width, height: height)
                let path = Path(roundedRect: rect, cornerRadius: width / 2)
                let color = Color(hue: 0.53 + Double(index) / Double(count) * 0.08, saturation: 0.85, brightness: 1)
                context.fill(path, with: .color(color.opacity(0.9)))
            }
        }
        .frame(height: 40)
        .padding(.horizontal, 4)
        .drawingGroup()
        .transaction { transaction in transaction.animation = nil }
    }
}
