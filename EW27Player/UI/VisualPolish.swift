import SwiftUI
import UIKit

struct ArtworkAuroraBackground: View {
    let image: UIImage?
    let tint: UIColor?
    @State private var isAnimating = false

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
                .offset(x: isAnimating ? 110 : -90, y: isAnimating ? -170 : -40)
            Circle()
                .fill(Color.blue.opacity(0.12))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: isAnimating ? -120 : 80, y: isAnimating ? 230 : 110)
            LinearGradient(
                colors: [accent.opacity(0.16), .black.opacity(0.28), .black.opacity(0.90)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .onAppear {
            guard !isAnimating else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

struct PlaybackGlow: View {
    let isActive: Bool
    @State private var pulsing = false

    var body: some View {
        Circle()
            .stroke(Color.cyan.opacity(isActive ? 0.42 : 0), lineWidth: 2)
            .scaleEffect(pulsing && isActive ? 1.22 : 1)
            .opacity(pulsing && isActive ? 0.15 : (isActive ? 0.7 : 0))
            .animation(
                isActive
                    ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
                    : .easeOut(duration: 0.2),
                value: pulsing
            )
            .onAppear { pulsing = isActive }
            .onChange(of: isActive) { _, value in pulsing = value }
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
