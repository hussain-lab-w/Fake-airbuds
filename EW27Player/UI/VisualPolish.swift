import SwiftUI
import UIKit

struct ArtworkAuroraBackground: View {
    let image: UIImage?
    let tint: UIColor?
    private var accent: Color {
        tint.map(Color.init(uiColor:)) ?? Color(red: 0.08, green: 0.32, blue: 0.58)
    }

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.035, blue: 0.065)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.12)
                    .blur(radius: 58)
                    .opacity(0.13)
                    .ignoresSafeArea()
            }
            Circle()
                .fill(accent.opacity(0.24))
                .frame(width: 320, height: 320)
                .blur(radius: 76)
                .offset(x: 90, y: -130)
            Circle()
                .fill(Color.blue.opacity(0.12))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: -80, y: 170)
            LinearGradient(
                colors: [accent.opacity(0.16), .black.opacity(0.28), .black.opacity(0.90)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

struct GlassPanel<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content

    init(cornerRadius: CGFloat = 24, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    }
}
