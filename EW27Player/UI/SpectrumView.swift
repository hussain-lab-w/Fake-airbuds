import SwiftUI

struct SpectrumView: View {
    let bars: [Float]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, value in
                Capsule()
                    .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom))
                    .frame(height: max(3, CGFloat(value) * 64))
            }
        }
        .frame(height: 68, alignment: .bottom)
        .padding(.horizontal, 4)
    }
}
