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

    func body(content: Content) -> some View {
        content.liquidGlass(prominent: prominent)
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
                    // Kept fairly present: Liquid Glass refracts whatever is
                    // behind it, so a flat wash underneath makes every pane
                    // read as plain frosted material.
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(drift ? 1.16 : 1.10)
                        .offset(x: drift ? 12 : -10, y: drift ? -8 : 10)
                        .blur(radius: 38)
                        .opacity(colorScheme == .dark ? 0.55 : 0.42)
                        .transition(.opacity)
                        .id(artworkKey)
                }
                Circle().fill(accent.opacity(colorScheme == .dark ? 0.42 : 0.26)).frame(width: 340, height: 340).blur(radius: 84)
                    .offset(x: drift ? 112 : 64, y: drift ? -152 : -114)
                Circle().fill(accent.opacity(colorScheme == .dark ? 0.26 : 0.18)).frame(width: 300, height: 300).blur(radius: 90)
                    .offset(x: drift ? -100 : -60, y: drift ? 192 : 144)
                Ellipse().fill(shade.opacity(colorScheme == .dark ? 0.10 : 0.30)).frame(width: 420, height: 260).blur(radius: 70)
                    .offset(x: drift ? -40 : 20, y: drift ? -220 : -180)
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
        .ew27BackgroundExtension()
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
        content.liquidGlass(prominent: true)
    }
}

// MARK: - Liquid Glass surfaces
//
// One material language for the whole app. On iOS 26 every surface is a real
// Apple Liquid Glass layer (it refracts whatever sits behind it); on iOS 17-25
// the same call sites fall back to a layered material so the layout, spacing
// and hierarchy stay identical across systems.

enum EW27Radius {
    static let panel: CGFloat = 26
    static let card: CGFloat = 22
    static let row: CGFloat = 18
    static let chip: CGFloat = 14
}

struct GlassSurfaceModifier<S: Shape>: ViewModifier {
    var shape: S
    var isProminent = false
    var tint: Color?
    var isInteractive = false
    /// Lets the backdrop show through more strongly. Reserved for surfaces that
    /// float over artwork, where legibility is not carried by the pane itself.
    var isTranslucent = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                content
                    .glassEffect(glass, in: shape)
                    .overlay { specular }
            }
            .shadow(
                color: .black.opacity(isProminent ? 0.20 : 0.10),
                radius: reduceMotion || reduceTransparency ? 0 : (isProminent ? 14 : 8),
                y: reduceMotion || reduceTransparency ? 0 : (isProminent ? 6 : 3)
            )
        } else {
            fallback(content)
        }
    }

    /// The refraction surface. `.clear` lets the artwork read through on the
    /// floating panes; `.regular` keeps text legible on content panes.
    @available(iOS 26.0, *)
    private var glass: Glass {
        var value: Glass = isTranslucent ? .clear : .regular
        if let tint { value = value.tint(tint) }
        if isInteractive { value = value.interactive() }
        return value
    }

    /// The specular edge: a bright top rim fading to a faint bottom rim. This is
    /// what reads as a pane of glass rather than a flat translucent rectangle.
    private var specular: some View {
        shape.stroke(
            LinearGradient(
                colors: [
                    .white.opacity(colorScheme == .dark ? 0.34 : 0.52),
                    .white.opacity(colorScheme == .dark ? 0.06 : 0.14),
                    .white.opacity(colorScheme == .dark ? 0.10 : 0.24)
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            lineWidth: 0.8
        )
        .allowsHitTesting(false)
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(
                reduceTransparency
                    ? AnyShapeStyle(.thickMaterial)
                    : (isProminent ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.thinMaterial)),
                in: shape
            )
            .overlay { specular }
            .shadow(
                color: .black.opacity(isProminent ? 0.18 : 0.09),
                radius: reduceMotion || reduceTransparency ? 0 : (isProminent ? 12 : 7),
                y: reduceMotion || reduceTransparency ? 0 : (isProminent ? 5 : 3)
            )
    }
}

extension View {
    /// A Liquid Glass panel. `prominent` lifts it above the page.
    func liquidGlass(
        prominent: Bool = false,
        tint: Color? = nil,
        interactive: Bool = false,
        translucent: Bool = false
    ) -> some View {
        modifier(GlassSurfaceModifier(
            shape: RoundedRectangle(cornerRadius: prominent ? EW27Radius.panel : EW27Radius.card, style: .continuous),
            isProminent: prominent,
            tint: tint,
            isInteractive: interactive,
            isTranslucent: translucent
        ))
    }

    /// A tappable glass list row or card.
    func glassRow(isSelected: Bool = false, radius: CGFloat = EW27Radius.row) -> some View {
        modifier(GlassSurfaceModifier(
            shape: RoundedRectangle(cornerRadius: radius, style: .continuous),
            tint: isSelected ? EW27Design.accent.opacity(0.24) : nil,
            isInteractive: true
        ))
    }

    /// A glass capsule — filter chips, speed presets, badges.
    func glassChip(isSelected: Bool = false) -> some View {
        modifier(GlassSurfaceModifier(
            shape: Capsule(),
            tint: isSelected ? EW27Design.accent.opacity(0.32) : nil,
            isInteractive: true
        ))
    }

    /// A glass circle — transport and toolbar buttons.
    func glassCircle(isActive: Bool = false, tint: Color? = nil) -> some View {
        modifier(GlassSurfaceModifier(
            shape: Circle(),
            tint: tint ?? (isActive ? EW27Design.accent.opacity(0.32) : nil),
            isInteractive: true
        ))
    }
}


private struct BackgroundExtensionModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.backgroundExtensionEffect()
        } else {
            content
        }
    }
}

extension View {
    /// Extends the backdrop under adjacent glass bars and the safe area.
    func ew27BackgroundExtension() -> some View {
        modifier(BackgroundExtensionModifier())
    }
}

/// Swaps a symbol with a spring morph instead of a hard cut.
struct EW27SymbolReplace: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.contentTransition(.symbolEffect(.replace))
        } else {
            content
        }
    }
}

extension View {
    func ew27SymbolReplace() -> some View { modifier(EW27SymbolReplace()) }
}

/// Play/pause drawn from shapes so the two states spring into each other.
struct EW27PlayPauseIcon: View {
    let isPlaying: Bool
    var size: CGFloat = 20
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: CGFloat { isPlaying ? 1 : 0 }

    var body: some View {
        ZStack {
            Image(systemName: "play.fill")
                .font(.system(size: size, weight: .semibold))
                .opacity(1 - progress)
                .scaleEffect(1 - progress * 0.18)
                .offset(x: progress * size * 0.14)
            HStack(spacing: max(3, size * 0.17)) {
                RoundedRectangle(cornerRadius: max(1.5, size * 0.07), style: .continuous)
                    .frame(width: max(3.5, size * 0.22), height: size * 0.84)
                RoundedRectangle(cornerRadius: max(1.5, size * 0.07), style: .continuous)
                    .frame(width: max(3.5, size * 0.22), height: size * 0.84)
            }
            .opacity(progress)
            .scaleEffect(0.8 + progress * 0.2)
            .offset(x: (1 - progress) * -size * 0.14)
        }
        .frame(width: size * 1.3, height: size * 1.3)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78), value: isPlaying)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}

/// Groups neighbouring glass elements so iOS 26 can merge and morph them as one
/// continuous surface instead of stacking separate sheets of glass.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
