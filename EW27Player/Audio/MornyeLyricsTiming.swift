import Foundation

@MainActor
final class MornyeLyricsPlaybackClock {
    private var anchorPosition: TimeInterval = 0
    private var anchorDate = Date()
    private var hasAnchor = false

    func reset(to position: TimeInterval, at date: Date = Date()) {
        anchorPosition = max(0, position)
        anchorDate = date
        hasAnchor = true
    }

    func position(reported: TimeInterval, isPlaying: Bool, speed: Double, at date: Date = Date()) -> TimeInterval {
        let safeReported = max(0, reported)
        guard isPlaying, speed > 0 else {
            reset(to: safeReported, at: date)
            return safeReported
        }
        guard hasAnchor else {
            reset(to: safeReported, at: date)
            return safeReported
        }

        let elapsed = max(0, date.timeIntervalSince(anchorDate)) * speed
        let predicted = anchorPosition + elapsed
        let drift = safeReported - predicted
        if abs(drift) >= 0.75 {
            reset(to: safeReported, at: date)
            return safeReported
        }

        // Small reports are reconciled gradually, avoiding backward lyric jumps.
        let corrected = max(0, predicted + drift * 0.25)
        anchorPosition = corrected
        anchorDate = date
        return corrected
    }
}

enum MornyeLyricsTiming {
    static func normalized(_ lyrics: TrackLyrics) -> TrackLyrics {
        guard !lyrics.lines.isEmpty else { return lyrics }
        let sourceLines = lyrics.lines
        var output: [LyricLine] = []
        output.reserveCapacity(sourceLines.count)

        for index in sourceLines.indices {
            let line = sourceLines[index]
            guard !line.words.isEmpty else {
                output.append(line)
                continue
            }

            let nextLineStart = index + 1 < sourceLines.count ? sourceLines[index + 1].start : nil
            let pace = medianWordPace(line.words)
            var lineEnd: TimeInterval? = line.end > line.start ? line.end : nil
            let lastEnd = line.words.last?.end ?? 0
            if lastEnd > line.start {
                lineEnd = max(lineEnd ?? 0, lastEnd)
            }
            if lineEnd == nil, let nextLineStart, nextLineStart > line.start, nextLineStart - line.start <= 4 {
                lineEnd = nextLineStart
            }
            if lineEnd == nil {
                lineEnd = line.start + min(3, max(0.7, pace * 2.5))
            }

            var words: [LyricWord] = []
            words.reserveCapacity(line.words.count)
            for wordIndex in line.words.indices {
                let word = line.words[wordIndex]
                let nextWordStart = wordIndex + 1 < line.words.count ? line.words[wordIndex + 1].start : nil
                var end: TimeInterval? = word.end > word.start ? word.end : nil
                if end == nil, let nextWordStart, nextWordStart > word.start { end = nextWordStart }
                if end == nil, lineEnd! > word.start { end = lineEnd }
                if end == nil { end = word.start + min(3, max(0.7, pace * 2.5)) }
                words.append(LyricWord(text: word.text, start: word.start, end: max(word.start, end!)))
            }
            let finalEnd = max(line.start, max(lineEnd!, words.last?.end ?? line.start))
            output.append(LyricLine(start: line.start, end: finalEnd, words: words))
        }

        return TrackLyrics(lines: output, source: lyrics.source, hasWordTiming: lyrics.hasWordTiming, plainText: lyrics.plainText)
    }

    private static func medianWordPace(_ words: [LyricWord]) -> TimeInterval {
        let values = words.indices.dropLast().compactMap { index -> TimeInterval? in
            let delta = words[index + 1].start - words[index].start
            return delta > 0 ? delta : nil
        }.sorted()
        return values.isEmpty ? 0.65 : values[values.count / 2]
    }
}
