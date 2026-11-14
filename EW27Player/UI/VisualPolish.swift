import SwiftUI
import UIKit

enum Motion {
    static let snappy = Animation.snappy(duration: 0.2)
    static let sheet = Animation.spring(response: 0.4, dampingFraction: 0.85)
    static let crossfade = Animation.easeInOut(duration: 0.3)
}

struct MusicPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.68), value: configuration.isPressed)
    }
}

enum EW27Design {
    static let pagePadding: CGFloat = 20
    static let compactPadding: CGFloat = 14
    static let cardRadius: CGFloat = 22
    static let rowRadius: CGFloat = 16
    static let sectionGap: CGFloat = 16
    static let cyan = Color(red: 0.38, green: 0.78, blue: 1)
    static let pageBackground = Color(red: 0.018, green: 0.023, blue: 0.039)
}

struct EW27CardModifier: ViewModifier {
    let prominent: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(
                prominent ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.white.opacity(0.055)),
                in: RoundedRectangle(cornerRadius: EW27Design.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: EW27Design.cardRadius, style: .continuous)
                    .stroke(.white.opacity(prominent ? 0.14 : 0.09), lineWidth: 1)
            }
            .shadow(
                color: .black.opacity(prominent ? 0.22 : 0.10),
                radius: reduceMotion ? 0 : (prominent ? 18 : 8),
                y: reduceMotion ? 0 : (prominent ? 8 : 4)
            )
    }
}

extension View {
    func ew27Card(prominent: Bool = false) -> some View {
        modifier(EW27CardModifier(prominent: prominent))
    }
}

struct EW27SectionLabel: View {
    let title: String
    let systemImage: String?

    init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .font(.caption.weight(.bold))
        .tracking(1.15)
        .foregroundStyle(EW27Design.cyan)
        .textCase(nil)
        .accessibilityAddTraits(.isHeader)
    }
}

struct EW27LoadingState: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
                .tint(EW27Design.cyan)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.86))
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .ew27Card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

struct EW27EmptyState: View {
    let systemImage: String
    let title: String
    let detail: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(systemImage: String, title: String, detail: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(EW27Design.cyan)
                .frame(width: 64, height: 64)
                .background(EW27Design.cyan.opacity(0.12), in: Circle())
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.54))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .tint(EW27Design.cyan)
                    .buttonStyle(MusicPressStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
        .ew27Card()
        .accessibilityElement(children: .combine)
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
                EW27Design.pageBackground
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
