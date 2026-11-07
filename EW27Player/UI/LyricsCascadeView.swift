import SwiftUI

struct LyricsCascadeView: View {
    @ObservedObject var player: AudioPlayer
    @ObservedObject var store: LyricsStore
    let lines: [LyricLine]
    let fontSize: CGFloat
    let reduceMotion: Bool

    @State private var rowHeights: [Int: CGFloat] = [:]
    @State private var manualMode = false
    @State private var returnTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !player.isPlaying)) { context in
                let time = player.lyricPlaybackTime(at: context.date) + store.syncOffset
                let focus = focusIndex(at: time)
                ZStack(alignment: .topLeading) {
                    if manualMode {
                        manualScroll(focus: focus)
                            .transition(.opacity)
                    } else {
                        cascade(focus: focus, time: time, viewport: geo.size)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: manualMode)
                .overlay(alignment: .bottom) {
                    if manualMode {
                        Button { returnToCascade() } label: {
                            Label("Sync", systemImage: "arrow.down.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 12)
                    }
                }
                .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in enterManualMode() })
            }
        }
        .onDisappear { returnTask?.cancel() }
    }

    private func cascade(focus: Int, time: TimeInterval, viewport: CGSize) -> some View {
        let visible = lines.indices.filter { $0 >= max(0, focus - 10) && $0 <= min(lines.count - 1, focus + 14) }
        let tops = cumulativeTops()
        let anchorY = viewport.height * 0.30
        let focusY = tops[safe: focus] ?? 0
        return ZStack(alignment: .topLeading) {
            ForEach(visible, id: \.self) { index in
                CascadeLineView(line: lines[index], time: time, active: index == focus, fontSize: fontSize, reduceMotion: reduceMotion)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GeometryReader { proxy in Color.clear.preference(key: CascadeRowHeightKey.self, value: [index: proxy.size.height]) })
                    .offset(y: (tops[safe: index] ?? 0) + anchorY - focusY)
                    .animation(rowAnimation(index: index, focus: focus), value: focus)
                    .id(index)
            }
        }
        .padding(.horizontal, 24)
        .onPreferenceChange(CascadeRowHeightKey.self) { rowHeights.merge($0) { _, new in new } }
        .mask(edgeFade)
    }

    private func manualScroll(focus: Int) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 22) {
                    Color.clear.frame(height: 120)
                    ForEach(lines.indices, id: \.self) { index in
                        CascadeLineView(line: lines[index], time: player.elapsed, active: index == focus, fontSize: fontSize, reduceMotion: reduceMotion)
                            .id(index)
                    }
                    Color.clear.frame(height: 260)
                }
                .padding(.horizontal, 24)
            }
            .onAppear { withTransaction(Transaction(animation: nil)) { proxy.scrollTo(focus, anchor: .center) } }
        }
    }

    private func enterManualMode() {
        guard !manualMode else { return }
        manualMode = true
        returnTask?.cancel()
        returnTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            manualMode = false
        }
    }

    private func returnToCascade() {
        returnTask?.cancel()
        manualMode = false
    }

    private func focusIndex(at time: TimeInterval) -> Int {
        var low = 0, high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].start - 0.2 <= time { low = middle + 1 } else { high = middle }
        }
        return max(0, min(lines.count - 1, low - 1))
    }

    private func cumulativeTops() -> [CGFloat] {
        guard !lines.isEmpty else { return [] }
        var tops = Array(repeating: CGFloat.zero, count: lines.count)
        for index in 1..<lines.count { tops[index] = tops[index - 1] + (rowHeights[index - 1] ?? fontSize * 1.35) + 22 }
        return tops
    }

    private func rowAnimation(index: Int, focus: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        let distance = abs(index - focus)
        if distance > 3 { return .smooth(duration: 0.35) }
        let delay = index > focus ? min(0.35, Double(index - focus) * 0.045) : 0
        return .spring(response: 0.6, dampingFraction: 0.78).delay(delay)
    }

    private var edgeFade: some View {
        LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12), .init(color: .black, location: 0.86), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
    }
}

private struct CascadeRowHeightKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) { value.merge(nextValue()) { _, new in new } }
}

private struct CascadeLineView: View {
    let line: LyricLine
    let time: TimeInterval
    let active: Bool
    let fontSize: CGFloat
    let reduceMotion: Bool

    var body: some View {
        CascadeFlowLayout(horizontalSpacing: fontSize * 0.26, verticalSpacing: 2) {
            ForEach(Array(line.words.enumerated()), id: \.offset) { _, word in
                CascadeWordView(word: word, time: time, active: active, fontSize: fontSize)
            }
        }
        .scaleEffect(active || reduceMotion ? 1 : 0.92, anchor: .leading)
        .opacity(active ? 1 : 0.38)
        .blur(radius: reduceMotion || active ? 0 : min(6, max(0, abs(line.start - time) - 1) * 1.5))
        .contentShape(Rectangle())
    }
}

private struct CascadeWordView: View {
    let word: LyricWord
    let time: TimeInterval
    let active: Bool
    let fontSize: CGFloat

    private var progress: CGFloat { CGFloat(min(1, max(0, (time - word.start) / max(0.001, word.end - word.start)))) }
    private var backgroundVocal: Bool { word.text.hasPrefix("(") && word.text.hasSuffix(")") }
    private var scale: CGFloat { active && word.end - word.start > 1 ? 1 + 0.06 * sin(progress * .pi) : 1 }

    var body: some View {
        ZStack(alignment: .leading) {
            Text(word.text).foregroundStyle(.white.opacity(backgroundVocal ? 0.28 : 0.38))
            if active {
                Text(word.text).foregroundStyle(.white).mask(alignment: .leading) {
                    GeometryReader { proxy in
                        Rectangle().frame(width: proxy.size.width * progress)
                    }
                }
                .opacity(backgroundVocal ? 0.28 : 1)
                .shadow(color: .white.opacity(0.35), radius: 10)
            }
        }
        .font(.system(size: backgroundVocal ? fontSize * 0.72 : fontSize, weight: .bold, design: .default))
        .tracking(-0.4)
        .fixedSize(horizontal: true, vertical: false)
        .scaleEffect(scale, anchor: .bottomLeading)
        .offset(y: active && progress > 0 && progress < 1 ? -1.5 : 0)
    }
}

private struct CascadeFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += lineHeight + verticalSpacing; lineHeight = 0 }
            x += size.width + horizontalSpacing; lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += lineHeight + verticalSpacing; lineHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + horizontalSpacing; lineHeight = max(lineHeight, size.height)
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
