import SwiftUI
import UIKit

enum Motion {
    static let snappy = Animation.snappy(duration: 0.2)
    static let sheet = Animation.spring(response: 0.4, dampingFraction: 0.85)
    static let crossfade = Animation.easeInOut(duration: 0.3)
}

enum EW27Appearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Bright"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
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

    // Semantic colors resolve correctly in both Bright and Dark appearances.
    static let primaryText = Color(uiColor: .label)
    static let secondaryText = Color(uiColor: .secondaryLabel)
    static let tertiaryText = Color(uiColor: .tertiaryLabel)
    static let canvas = Color(uiColor: .systemBackground)
    static let groupedCanvas = Color(uiColor: .secondarySystemBackground)
    static let separator = Color(uiColor: .separator)
    static let cyan = Color(uiColor: .systemCyan)
    static let accent = Color(uiColor: .systemBlue)
}

struct EW27CardModifier: ViewModifier {
    let prominent: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(
                prominent ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.thinMaterial),
                in: RoundedRectangle(cornerRadius: EW27Design.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: EW27Design.cardRadius, style: .continuous)
                    .stroke(EW27Design.primaryText.opacity(prominent ? 0.16 : 0.09), lineWidth: 1)
            }
            .shadow(
                color: .black.opacity(prominent ? 0.18 : 0.08),
                radius: reduceMotion ? 0 : (prominent ? 14 : 7),
                y: reduceMotion ? 0 : (prominent ? 6 : 3)
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
            if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
        }
        .font(.caption.weight(.bold))
        .tracking(1.15)
        .foregroundStyle(EW27Design.accent)
        .textCase(nil)
        .accessibilityAddTraits(.isHeader)
    }
}

struct EW27LoadingState: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.regular).tint(EW27Design.accent)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(EW27Design.primaryText)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(EW27Design.secondaryText).multilineTextAlignment(.center)
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
                .foregroundStyle(EW27Design.accent)
                .frame(width: 64, height: 64)
                .background(EW27Design.accent.opacity(0.12), in: Circle())
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(EW27Design.primaryText)
            Text(detail)
                .font(.caption)
                .foregroundStyle(EW27Design.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .tint(EW27Design.accent)
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
    @Environment(\.colorScheme) private var colorScheme
    @State private var drift = false

    private var accent: Color { tint.map(Color.init(uiColor:)) ?? EW27Design.accent }
    private var artworkKey: String { "\(image?.hash ?? 0)-\(tint?.hash ?? 0)" }
    private var base: Color { colorScheme == .dark ? Color(red: 0.018, green: 0.023, blue: 0.039) : Color(red: 0.93, green: 0.96, blue: 1.0) }
    private var shade: Color { colorScheme == .dark ? .black : .white }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                base
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(drift ? 1.16 : 1.10)
                        .offset(x: drift ? 12 : -10, y: drift ? -8 : 10)
                        .blur(radius: 54)
                        .opacity(colorScheme == .dark ? 0.32 : 0.22)
                        .transition(.opacity)
                        .id(artworkKey)
                }
                Circle().fill(accent.opacity(colorScheme == .dark ? 0.30 : 0.18)).frame(width: 320, height: 320).blur(radius: 88)
                    .offset(x: drift ? 110 : 62, y: drift ? -150 : -112)
                Circle().fill(accent.opacity(colorScheme == .dark ? 0.16 : 0.10)).frame(width: 280, height: 280).blur(radius: 94)
                    .offset(x: drift ? -98 : -58, y: drift ? 190 : 142)
                LinearGradient(
                    colors: [accent.opacity(colorScheme == .dark ? 0.18 : 0.10), base.opacity(0.42), shade.opacity(colorScheme == .dark ? 0.82 : 0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: artworkKey)
        .onAppear { beginDrift() }
        .onChange(of: reduceMotion) { _, reduced in if reduced { drift = false } else { beginDrift() } }
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(EW27Design.primaryText.opacity(0.13), lineWidth: 1) }
    }
}

// Uses Apple's native Liquid Glass on iOS 26+, while retaining a lightweight iOS 17 fallback.
struct LiquidGlassModifier: ViewModifier {
    var isProminent = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var cornerRadius: CGFloat { isProminent ? 22 : 18 }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            if isProminent {
                content.glassEffect(.regular, in: shape)
            } else {
                content.glassEffect(.clear, in: shape)
            }
        } else {
            content
                .background(
                    isProminent ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.thinMaterial),
                    in: shape
                )
                .overlay {
                    LinearGradient(
                        colors: [EW27Design.primaryText.opacity(isProminent ? 0.10 : 0.06), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(shape)
                }
                .overlay {
                    shape.stroke(EW27Design.primaryText.opacity(isProminent ? 0.18 : 0.11), lineWidth: 1)
                }
                .shadow(
                    color: .black.opacity(isProminent ? 0.18 : 0.10),
                    radius: reduceMotion ? 0 : (isProminent ? 12 : 7),
                    y: reduceMotion ? 0 : (isProminent ? 5 : 3)
                )
        }
    }
}

extension View {
    func liquidGlass(prominent: Bool = false) -> some View {
        modifier(LiquidGlassModifier(isProminent: prominent))
    }
}
