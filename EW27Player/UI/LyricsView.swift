import SwiftUI
import UniformTypeIdentifiers

struct LyricsView: View {
    @ObservedObject var player: AudioPlayer
    @ObservedObject var store: LyricsStore

    @AppStorage("ew27.lyrics.fontSize.v1") private var fontSize = 22.0
    @State private var showImporter = false
    @State private var importError: String?
    @State private var autoScrollPaused = false
    @State private var resumeAutoScrollTask: Task<Void, Never>?

    private var trackLyrics: TrackLyrics? { store.lyrics }
    private var isSynced: Bool { trackLyrics?.isSynced == true }

    private var acceptedFileTypes: [UTType] {
        [.plainText, UTType(filenameExtension: "lrc") ?? .plainText, UTType(filenameExtension: "ttml") ?? .xml]
    }

    private var sourceBadge: String {
        guard let lyrics = trackLyrics else { return store.isLoading ? "Looking up lyrics…" : "No lyrics found" }
        switch lyrics.source {
        case .lrclib:
            if lyrics.lines.isEmpty { return "LRCLIB · unsynced" }
            return lyrics.hasWordTiming ? "LRCLIB · word-synced" : "LRCLIB · word timing estimated"
        case .imported:
            if lyrics.lines.isEmpty { return "Imported · unsynced" }
            return lyrics.hasWordTiming ? "Imported · word-synced" : "Imported · word timing estimated"
        case .embeddedPlain:
            return "Embedded · unsynced"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text(player.currentItem?.title ?? "No track selected")
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(player.currentItem?.artist ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(sourceBadge)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.white.opacity(0.08)))
                    Spacer(minLength: 4)
                    if !isSynced {
                        Button("A−") { fontSize = max(14, fontSize - 2) }
                            .disabled(fontSize <= 14)
                            .accessibilityLabel("Decrease lyrics text size")
                        Button("A+") { fontSize = min(30, fontSize + 2) }
                            .disabled(fontSize >= 30)
                            .accessibilityLabel("Increase lyrics text size")
                    }
                    Button { showImporter = true } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 32, height: 30)
                    }
                    .buttonStyle(.bordered)
                    .tint(.cyan)
                    .accessibilityLabel("Import lyrics")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.cyan)

                if let importError {
                    Text(importError)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 12)

            if isSynced, let lines = trackLyrics?.lines {
                VStack(spacing: 0) {
                    offsetBar
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
                        let sourceTime = player.clock.elapsed
                        let currentTime = sourceTime + store.syncOffset
                        let activeIndex = activeLineIndex(in: lines, at: currentTime)
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 24) {
                                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                        FlowLayout(spacing: 7) {
                                            ForEach(Array(line.words.enumerated()), id: \.offset) { _, word in
                                                SyncedLyricWord(word: word, time: currentTime, isActiveLine: index == activeIndex)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .scaleEffect(index == activeIndex ? 1.03 : 1, anchor: .leading)
                                        .opacity(index == activeIndex ? 1 : 0.35)
                                        .animation(.easeOut(duration: 0.18), value: index == activeIndex)
                                        .contentShape(Rectangle())
                                        .id(index)
                                        .onTapGesture { player.seek(to: line.start) }
                                        .accessibilityElement(children: .combine)
                                        .accessibilityAddTraits(.isButton)
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.top, 22)
                                .padding(.bottom, 120)
                            }
                            .simultaneousGesture(DragGesture(minimumDistance: 3).onChanged { _ in pauseAutoScroll() })
                            .onChange(of: activeIndex) { _, index in
                                guard !autoScrollPaused, let index else { return }
                                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(index, anchor: .center) }
                            }
                            .onChange(of: autoScrollPaused) { _, paused in
                                guard !paused, let activeIndex else { return }
                                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(activeIndex, anchor: .center) }
                            }
                        }
                    }
                }
            } else if let lyrics = trackLyrics, !lyrics.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                unsyncedLyrics(lyrics.plainText)
            } else {
                Spacer(minLength: 0)
                VStack(spacing: 12) {
                    if store.isLoading {
                        ProgressView()
                            .tint(.cyan)
                        Text("Looking up lyrics…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "quote.bubble")
                            .font(.system(size: 42, weight: .light))
                            .foregroundStyle(.white.opacity(0.42))
                        Text("No lyrics found")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: acceptedFileTypes, allowsMultipleSelection: false, onCompletion: handleImport)
        .onDisappear { resumeAutoScrollTask?.cancel() }
    }

    private var offsetBar: some View {
        HStack(spacing: 10) {
            Button { store.adjustSyncOffset(by: -0.1) } label: {
                Image(systemName: "minus.circle.fill")
            }
            .accessibilityLabel("Decrease sync offset by 0.1 seconds")
            Text(String(format: "%+.1f s", store.syncOffset))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.cyan)
            Button { store.adjustSyncOffset(by: 0.1) } label: {
                Image(systemName: "plus.circle.fill")
            }
            .accessibilityLabel("Increase sync offset by 0.1 seconds")
            Spacer()
        }
        .font(.system(size: 15, weight: .semibold))
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.78))
        .padding(.horizontal, 24)
        .padding(.top, 3)
        .padding(.bottom, 5)
    }

    private func unsyncedLyrics(_ text: String) -> some View {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let stanzas = normalized.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        ScrollView {
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
                                        .font(.system(size: CGFloat(min(30, max(14, fontSize))), weight: .semibold, design: .rounded))
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
            .padding(.bottom, 120)
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white, location: 0.09),
                    .init(color: .white, location: 0.91),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func activeLineIndex(in lines: [LyricLine], at time: TimeInterval) -> Int? {
        guard let first = lines.first, time >= first.start else { return nil }
        var lower = 0
        var upper = lines.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if lines[middle].start <= time { lower = middle + 1 }
            else { upper = middle }
        }
        let index = lower - 1
        guard lines.indices.contains(index), time <= lines[index].end else { return nil }
        return index
    }

    private func pauseAutoScroll() {
        autoScrollPaused = true
        resumeAutoScrollTask?.cancel()
        resumeAutoScrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            autoScrollPaused = false
        }
    }

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

private struct SyncedLyricWord: View {
    let word: LyricWord
    let time: TimeInterval
    let isActiveLine: Bool

    private var progress: CGFloat {
        guard word.end > word.start else { return time >= word.start ? 1 : 0 }
        return CGFloat(min(1, max(0, (time - word.start) / (word.end - word.start))))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Text(word.text)
                .foregroundStyle(.white.opacity(isActiveLine ? 0.35 : 1))
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
            }
        }
        .font(.system(size: 22, weight: .semibold, design: .rounded))
        .fixedSize(horizontal: true, vertical: false)
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
