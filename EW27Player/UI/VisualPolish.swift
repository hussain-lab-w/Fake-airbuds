import SwiftUI
import UIKit

struct MusicPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.68), value: configuration.isPressed)
    }
}

struct ArtworkAuroraBackground: View {
    let image: UIImage?
    let tint: UIColor?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    private var accent: Color {
        tint.map(Color.init(uiColor:)) ?? Color(red: 0.08, green: 0.32, blue: 0.58)
    }

    private var artworkKey: String { "\(image?.hash ?? 0)-\(tint?.hash ?? 0)" }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0.018, green: 0.023, blue: 0.039)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(drift ? 1.20 : 1.10)
                        .offset(x: drift ? 18 : -14, y: drift ? -12 : 14)
                        .blur(radius: 54)
                        .opacity(0.36)
                        .transition(.opacity)
                        .id(artworkKey)
                }
                Circle()
                    .fill(accent.opacity(0.34))
                    .frame(width: 320, height: 320)
                    .blur(radius: 88)
                    .offset(x: drift ? 110 : 62, y: drift ? -150 : -112)
                Circle()
                    .fill(accent.opacity(0.17))
                    .frame(width: 280, height: 280)
                    .blur(radius: 94)
                    .offset(x: drift ? -98 : -58, y: drift ? 190 : 142)
                LinearGradient(
                    colors: [accent.opacity(0.20), Color(red: 0.015, green: 0.02, blue: 0.04).opacity(0.58), .black.opacity(0.94)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.1), value: artworkKey)
        .onAppear { beginDrift() }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { drift = false } else { beginDrift() }
        }
    }

    private func beginDrift() {
        guard !reduceMotion, !drift else { if reduceMotion { drift = false }; return }
        withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) { drift = true }
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
