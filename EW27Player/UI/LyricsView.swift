import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LyricsView: View {
    @ObservedObject var player: AudioPlayer
    @ObservedObject var store: LyricsStore

    @AppStorage("ew27.lyrics.fontSize.v2") private var fontSize = 30.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showImporter = false
    @State private var importError: String?
    @State private var autoScrollPaused = false
    @State private var resumeAutoScrollTask: Task<Void, Never>?

    private static let gapThreshold: TimeInterval = 3.5
    private static let scrollAnchor = UnitPoint(x: 0.5, y: 0.38)

    private var trackLyrics: TrackLyrics? { store.lyrics }
    private var isSynced: Bool { trackLyrics?.isSynced == true }

    private var acceptedFileTypes: [UTType] {
        [.plainText, UTType(filenameExtension: "lrc") ?? .plainText, UTType(filenameExtension: "ttml") ?? .xml]
    }

    private var lineAnimation: Animation? {
        reduceMotion ? nil : Animation.interpolatingSpring(stiffness: 118, damping: 18)
    }

    private var sourceBadge: String {
        guard let lyrics = trackLyrics else { return store.isLoading ? "Looking up lyrics…" : "No lyrics found" }
        switch lyrics.source {
        case .lrclib:
            if lyrics.lines.isEmpty { return "LRCLIB · unsynced" }
            return lyrics.hasWordTiming ? "LRCLIB · word-synced" : "LRCLIB · word timing estimated"
        case .netease:
            return lyrics.hasWordTiming ? "NetEase · word-synced" : "NetEase · line-synced"
        case .appleMusic:
            return lyrics.hasWordTiming ? "Apple Music · word-synced" : "Apple Music · line-synced"
        case .lyricsOvh:
            return "Lyrics.ovh · unsynced"
        case .imported:
            if lyrics.lines.isEmpty { return "Imported · unsynced" }
            return lyrics.hasWordTiming ? "Imported · word-synced" : "Imported · word timing estimated"
        case .embeddedPlain:
            return "Embedded · unsynced"
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                if let importError {
                    Text(importError)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 4)
                }
                content
            }
            if isSynced { syncPill }
            LyricsTransportBar(player: player, clock: player.clock)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: acceptedFileTypes, allowsMultipleSelection: false, onCompletion: handleImport)
        .onDisappear { resumeAutoScrollTask?.cancel() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Group {
                if let image = player.currentArtwork {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.white.opacity(0.1)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentItem?.title ?? "No track selected")
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Text(player.currentItem?.artist ?? "")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)

            Menu {
                Button { showImporter = true } label: {
                    Label("Import lyrics file", systemImage: "square.and.arrow.down")
                }
                if isSynced {
                    Section("Sync offset (\(String(format: "%+.1f", store.syncOffset)) s)") {
                        Button { store.adjustSyncOffset(by: -0.1) } label: {
                            Label("−0.1 s", systemImage: "minus.circle")
                        }
                        Button { store.adjustSyncOffset(by: 0.1) } label: {
                            Label("+0.1 s", systemImage: "plus.circle")
                        }
                    }
                }
                Section("Text size (\(Int(fontSize)))") {
                    Button { fontSize = max(24, fontSize - 2) } label: {
                        Label("Smaller", systemImage: "textformat.size.smaller")
                    }
                    Button { fontSize = min(38, fontSize + 2) } label: {
                        Label("Larger", systemImage: "textformat.size.larger")
                    }
                }
                Section("Source") {
                    Text(sourceBadge)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isSynced, let lines = trackLyrics?.lines {
            syncedContent(lines)
        } else if let lyrics = trackLyrics, !lyrics.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            unsyncedLyrics(lyrics.plainText)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            if store.isLoading {
                ProgressView().tint(.cyan)
                Text("Looking up lyrics…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.white.opacity(0.42))
                Text("No lyrics for this track")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button { showImporter = true } label: {
                    Label("Import lyrics file", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .tint(.cyan)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Synced lyrics

    private func syncedContent(_ lines: [LyricLine]) -> some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !player.isPlaying)) { context in
                let time = player.lyricPlaybackTime(at: context.date) + store.syncOffset
                let state = playbackState(lines: lines, time: time)
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            Color.clear.frame(height: geo.size.height * 0.38)
                            ForEach(rows(for: lines)) { row in
                                rowView(row, lines: lines, time: time, state: state)
                            }
                            Color.clear.frame(height: geo.size.height * 0.62 + 120)
                        }
                        .padding(.leading, 24)
                        .padding(.trailing, 20)
                    }
                    .simultaneousGesture(DragGesture(minimumDistance: 3).onChanged { _ in pauseAutoScroll() })
                    .onChange(of: state.scrollID) { _, id in
                        guard !autoScrollPaused, let id else { return }
                        withAnimation(.easeInOut(duration: 0.72)) { proxy.scrollTo(id, anchor: Self.scrollAnchor) }
                    }
                    .onChange(of: autoScrollPaused) { _, paused in
                        guard !paused, let id = state.scrollID else { return }
                        withAnimation(.easeInOut(duration: 0.72)) { proxy.scrollTo(id, anchor: Self.scrollAnchor) }
                    }
                    .mask(edgeFade(height: geo.size.height))
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: LyricRow, lines: [LyricLine], time: TimeInterval, state: LyricsPlaybackState) -> some View {
        switch row {
        case .gap(let index):
            InterludeDots(
                start: index < 0 ? 0 : singEnd(for: lines[index]),
                end: lines[index + 1].start,
                time: time
            )
            .id(row.id)
        case .line(let index):
            lineView(index: index, line: lines[index], time: time, state: state)
                .id(row.id)
        }
    }

    private func lineView(index: Int, line: LyricLine, time: TimeInterval, state: LyricsPlaybackState) -> some View {
        let isSinging = state.singingIndex == index
        let isPast = index < state.focusIndex || (index == state.focusIndex && !isSinging)
        let distance = abs(index - max(state.focusIndex, 0))
        let lineTime = mappedTime(time, for: line)
        let relaxed = autoScrollPaused
        let opacity: Double = isSinging ? 1 : (relaxed ? 0.6 : 0.38)
        let blurRadius: CGFloat = (reduceMotion || relaxed || isSinging) ? 0 : CGFloat(min(6, Double(max(0, distance - 1)) * 1.5))
        return FlowLayout(spacing: CGFloat(fontSize) * 0.26) {
            ForEach(Array(line.words.enumerated()), id: \.offset) { _, word in
                SyncedLyricWord(word: word, time: lineTime, isActiveLine: isSinging, fontSize: CGFloat(fontSize))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scaleEffect(isSinging || reduceMotion ? 1 : 0.94, anchor: .leading)
        .opacity(opacity)
        .blur(radius: blurRadius)
        .animation(lineAnimation, value: state.focusIndex)
        .animation(lineAnimation, value: isSinging)
        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .bottom)), removal: .opacity))
        .contentShape(Rectangle())
        .onTapGesture { player.seek(to: line.start) }
        .contextMenu {
            Button {
                UIPasteboard.general.string = line.words.map { $0.text }.joined(separator: " ")
            } label: {
                Label("Copy line", systemImage: "doc.on.doc")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func edgeFade(height: CGFloat) -> some View {
        let h = max(height, 1)
        let top = min(0.2, 60 / h)
        let bottomStart = max(0.5, 1 - 170 / h)
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: top),
                .init(color: .black, location: bottomStart),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder
    private var syncPill: some View {
        if autoScrollPaused {
            Button { resumeAutoScroll() } label: {
                Label("Sync", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 140)
            .transition(.opacity)
        }
    }

    // MARK: - Timing helpers

    /// Estimated end of the actual singing for a line. LRC lines end where the next one starts,
    /// so long instrumental gaps would otherwise stretch the last words of the line.
    private func singEnd(for line: LyricLine) -> TimeInterval {
        let characters = Double(line.words.reduce(0) { $0 + $1.text.count })
        let estimate = max(1.2, characters * 0.09 + 0.6)
        let full = line.end - line.start
        return full > estimate * 2 + 1.5 ? line.start + estimate * 1.4 : line.end
    }

    /// Compresses the timeline of a line with a long gap so words sweep at a natural speed.
    private func mappedTime(_ time: TimeInterval, for line: LyricLine) -> TimeInterval {
        let sungEnd = singEnd(for: line)
        guard sungEnd < line.end, time > line.start else { return time }
        if time >= sungEnd { return line.end }
        let ratio = (line.end - line.start) / max(0.001, sungEnd - line.start)
        return line.start + (time - line.start) * ratio
    }

    private func playbackState(lines: [LyricLine], time: TimeInterval) -> LyricsPlaybackState {
        var lower = 0
        var upper = lines.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if lines[middle].start <= time { lower = middle + 1 } else { upper = middle }
        }
        let focus = lower - 1
        if focus < 0 {
            if let first = lines.first, first.start > Self.gapThreshold {
                return LyricsPlaybackState(focusIndex: -1, singingIndex: nil, scrollID: "gap-1")
            }
            return LyricsPlaybackState(focusIndex: -1, singingIndex: nil, scrollID: nil)
        }
        let line = lines[focus]
        let sungEnd = singEnd(for: line)
        if time < sungEnd {
            return LyricsPlaybackState(focusIndex: focus, singingIndex: focus, scrollID: "line\(focus)")
        }
        if focus + 1 < lines.count, lines[focus + 1].start - sungEnd > Self.gapThreshold {
                return LyricsPlaybackState(focusIndex: focus, singingIndex: nil, scrollID: line.end - line.start < 0.6 ? nil : "gap\(focus)")
            }
        return LyricsPlaybackState(focusIndex: focus, singingIndex: nil, scrollID: line.end - line.start < 0.6 ? nil : "line\(focus)")
    }

    private func rows(for lines: [LyricLine]) -> [LyricRow] {
        var result: [LyricRow] = []
        if let first = lines.first, first.start > Self.gapThreshold { result.append(.gap(-1)) }
        for index in lines.indices {
            result.append(.line(index))
            if index + 1 < lines.count, lines[index + 1].start - singEnd(for: lines[index]) > Self.gapThreshold {
                result.append(.gap(index))
            }
        }
        return result
    }

    private func pauseAutoScroll() {
        autoScrollPaused = true
        resumeAutoScrollTask?.cancel()
        resumeAutoScrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            autoScrollPaused = false
        }
    }

    private func resumeAutoScroll() {
        resumeAutoScrollTask?.cancel()
        autoScrollPaused = false
    }

    // MARK: - Unsynced lyrics

    private func unsyncedLyrics(_ text: String) -> some View {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let stanzas = normalized.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let size = CGFloat(min(30, max(16, fontSize * 0.8)))
        return ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(Array(stanzas.enumerated()), id: \.offset) { _, stanza in
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(stanza.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, rawLine in
                            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !line.isEmpty {
                                if line.hasPrefix("[") && line.hasSuffix("]") {
                                    Text(line.uppercased())
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .tracking(1.2)
                                        .foregroundStyle(.cyan)
                                } else {
                                    Text(rawLine)
                                        .font(.system(size: size, weight: .semibold, design: .rounded))
                                        .lineSpacing(8)
                                        .foregroundStyle(.white.opacity(0.92))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 160)
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.06),
                    .init(color: .black, location: 0.82),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Import

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first, let id = store.currentTrackID else { return }
            let hasSecurityScope = url.startAccessingSecurityScopedResource()
            defer { if hasSecurityScope { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let parsed = LyricsParser.parse(String(decoding: data, as: UTF8.self), source: .imported)
                guard !parsed.lines.isEmpty || !parsed.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    importError = "No lyrics could be read from this file."
                    return
                }
                store.importLyrics(parsed, for: id)
                importError = nil
            } catch {
                importError = error.localizedDescription
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}

// MARK: - Supporting types

private enum LyricRow: Identifiable {
    case line(Int)
    case gap(Int)

    var id: String {
        switch self {
        case .line(let index): return "line\(index)"
        case .gap(let index): return "gap\(index)"
        }
    }
}

private struct LyricsPlaybackState {
    var focusIndex: Int
    var singingIndex: Int?
    var scrollID: String?
}

private struct InterludeDots: View {
    let start: TimeInterval
    let end: TimeInterval
    let time: TimeInterval

    private var progress: Double {
        guard end > start else { return 0 }
        return min(1, max(0, (time - start) / (end - start)))
    }

    private var isVisible: Bool { time >= start - 0.2 && time <= end }
    private var breathingScale: CGFloat { CGFloat(1.0 + 0.18 * sin(progress * .pi * 2)) }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                let fill = min(1, max(0, progress * 3 - Double(index)))
                Circle()
                    .fill(.white.opacity(0.25 + 0.75 * fill))
                    .frame(width: 12, height: 12)
                    .scaleEffect(breathingScale * CGFloat(0.9 + 0.1 * fill))
            }
        }
        .padding(.vertical, 14)
        .opacity(isVisible ? (time > end - 0.3 ? max(0, (end - time) / 0.3) : 1) : 0.15)
        .animation(.easeInOut(duration: 0.3), value: isVisible)
    }
}

private struct SyncedLyricWord: View {
    let word: LyricWord
    let time: TimeInterval
    let isActiveLine: Bool
    let fontSize: CGFloat

    private var progress: CGFloat {
        guard word.end > word.start else { return time >= word.start ? 1 : 0 }
        return CGFloat(min(1, max(0, (time - word.start) / (word.end - word.start))))
    }

    private var isCurrent: Bool { isActiveLine && progress > 0 && progress < 1 }
    private var isBackgroundVocal: Bool { word.text.hasPrefix("(") && word.text.hasSuffix(")") }
    private var longWordScale: CGFloat {
        guard isCurrent, word.end - word.start > 1 else { return 1 }
        return 1 + 0.06 * sin(progress * .pi)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Text(word.text)
                .foregroundStyle(.white.opacity(isBackgroundVocal ? 0.28 : 0.38))
            if isActiveLine {
                Text(word.text)
                    .foregroundStyle(.white)
                    .mask {
                        GeometryReader { geometry in
                            if progress <= 0 {
                                Color.clear
                            } else if progress >= 1 {
                                Color.white
                            } else {
                                let revealWidth = geometry.size.width * progress
                                let featherWidth = min(16, max(4, geometry.size.width * 0.14))
                                let solidWidth = max(0, revealWidth - featherWidth)
                                let fadeWidth = max(0, revealWidth - solidWidth)
                                HStack(spacing: 0) {
                                    Rectangle().fill(.white).frame(width: solidWidth)
                                    LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                                        .frame(width: fadeWidth)
                                    Spacer(minLength: 0)
                                }
                                .frame(width: geometry.size.width, alignment: .leading)
                            }
                        }
                    }
                    .opacity(isBackgroundVocal ? 0.28 : 1)
                    .shadow(color: .white.opacity(isCurrent ? 0.35 : 0), radius: 10)
            }
        }
        .font(.system(size: isBackgroundVocal ? fontSize * 0.72 : fontSize, weight: .bold, design: .default))
        .tracking(-0.4)
        .fixedSize(horizontal: true, vertical: false)
        .scaleEffect(longWordScale, anchor: .bottomLeading)
        .offset(y: isCurrent ? -1.5 : 0)
        .animation(.easeInOut(duration: 0.22), value: isCurrent)
    }
}

/// Floating glass transport bar shown at the bottom of the lyrics page.
private struct LyricsTransportBar: View {
    @ObservedObject var player: AudioPlayer
    @ObservedObject var clock: PlaybackClock
    @State private var scrubFraction: Double?

    private func fraction(at elapsed: TimeInterval) -> Double {
        guard clock.duration > 0 else { return 0 }
        return min(1, max(0, elapsed / clock.duration))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !player.isPlaying)) { context in
            let elapsed = player.lyricPlaybackTime(at: context.date)
            let currentFraction = fraction(at: elapsed)
            VStack(spacing: 6) {
            GeometryReader { geo in
                let shown = scrubFraction ?? currentFraction
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().fill(.white.opacity(0.9)).frame(width: max(4, geo.size.width * shown))
                }
                .frame(height: 5)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            scrubFraction = min(1, max(0, value.location.x / max(1, geo.size.width)))
                        }
                        .onEnded { value in
                            let target = min(1, max(0, value.location.x / max(1, geo.size.width)))
                            player.seek(to: target * clock.duration)
                            scrubFraction = nil
                        }
                )
            }
            .frame(height: 22)

            HStack {
                Text(formatTime(scrubFraction.map { $0 * clock.duration } ?? elapsed))
                Spacer()
                Text("-" + formatTime(max(0, clock.duration - (scrubFraction.map { $0 * clock.duration } ?? elapsed))))
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))

            HStack(spacing: 40) {
                Button { player.previousTrack() } label: {
                    Image(systemName: "backward.fill").font(.system(size: 24))
                }
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 34))
                        .frame(width: 44, height: 44)
                }
                Button { player.nextTrack() } label: {
                    Image(systemName: "forward.fill").font(.system(size: 24))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        }
    }

    private func formatTime(_ value: TimeInterval) -> String {
        guard value.isFinite else { return "0:00" }
        let total = max(0, Int(value.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let measuredWidth = subviews.reduce(CGFloat.zero) { $0 + $1.sizeThatFits(.unspecified).width }
        let widthLimit = max(1, proposal.width ?? measuredWidth)
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0 && rowWidth + spacing + size.width > widthLimit {
                widestRow = max(widestRow, rowWidth)
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            if rowWidth > 0 { rowWidth += spacing }
            rowWidth += size.width
            rowHeight = max(rowHeight, size.height)
        }
        widestRow = max(widestRow, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: proposal.width ?? widestRow, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
