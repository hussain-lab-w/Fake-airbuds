import Foundation

private struct RawLyricLine {
    var start: TimeInterval
    var text: String
    var wordSegments: [RawWordSegment]
}

private struct RawWordSegment {
    var text: String
    var start: TimeInterval?
    var end: TimeInterval?
}

private struct RawTTMLLine {
    var start: TimeInterval
    var end: TimeInterval?
    var text: String
    var segments: [RawWordSegment]
}

private struct TTMLSpan {
    var text = ""
    var start: TimeInterval?
    var end: TimeInterval?
    var hasChild = false
}

enum LyricsParser {
    private static let lineTimestampRegex = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:\.(\d{1,3}))?\]"#)
    private static let wordTimestampRegex = try! NSRegularExpression(pattern: #"<(\d{1,3}):(\d{2})(?:\.(\d{1,3}))?>"#)
    private static let offsetRegex = try! NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: [.caseInsensitive])

    static func parse(_ text: String, source: LyricsSource = .imported) -> TrackLyrics {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: "<tt", options: .caseInsensitive) != nil || trimmed.range(of: "<p ", options: .caseInsensitive) != nil {
            return parseTTML(Data(text.utf8), source: source)
        }
        if lineTimestampRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            return parseLRC(text, source: source)
        }
        return TrackLyrics(lines: [], source: source, hasWordTiming: false, plainText: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func parseLRC(_ text: String, source: LyricsSource = .lrclib) -> TrackLyrics {
        let fullRange = NSRange(text.startIndex..., in: text)
        let offsetMilliseconds: Double
        if let match = offsetRegex.firstMatch(in: text, range: fullRange),
           let range = Range(match.range(at: 1), in: text),
           let value = Double(String(text[range])) {
            offsetMilliseconds = value
        } else {
            offsetMilliseconds = 0
        }
        let offset = offsetMilliseconds / 1000
        var rawLines: [RawLyricLine] = []

        for line in text.components(separatedBy: .newlines) {
            let range = NSRange(line.startIndex..., in: line)
            let matches = lineTimestampRegex.matches(in: line, range: range)
            guard !matches.isEmpty else { continue }
            let timestamps = matches.compactMap { timestamp(from: $0, in: line) }
            guard !timestamps.isEmpty else { continue }
            let body = lineTimestampRegex.stringByReplacingMatches(in: line, range: range, withTemplate: "")
            let plainBody = wordTimestampRegex.stringByReplacingMatches(
                in: body,
                range: NSRange(body.startIndex..., in: body),
                withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            let wordMatches = wordTimestampRegex.matches(in: body, range: NSRange(body.startIndex..., in: body))
            let firstOuterTimestamp = timestamps[0]

            for baseTimestamp in timestamps {
                let lineStart = max(0, baseTimestamp + offset)
                let shift = baseTimestamp - firstOuterTimestamp
                var segments: [RawWordSegment] = []
                for (index, wordMatch) in wordMatches.enumerated() {
                    guard let tagTime = timestamp(from: wordMatch, in: body) else { continue }
                    let chunkStart = wordMatch.range.location + wordMatch.range.length
                    let chunkEnd = index + 1 < wordMatches.count ? wordMatches[index + 1].range.location : (body as NSString).length
                    guard let chunkRange = Range(NSRange(location: chunkStart, length: max(0, chunkEnd - chunkStart)), in: body) else { continue }
                    let words = WordTiming.splitWords(String(body[chunkRange]))
                    guard !words.isEmpty else { continue }
                    segments.append(RawWordSegment(text: words.joined(separator: " "), start: max(0, tagTime + offset + shift), end: nil))
                }
                rawLines.append(RawLyricLine(start: lineStart, text: plainBody, wordSegments: segments))
            }
        }

        guard !rawLines.isEmpty else {
            return TrackLyrics(lines: [], source: source, hasWordTiming: false, plainText: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        rawLines.sort { $0.start < $1.start }
        var lines: [LyricLine] = []
        var hasWordTiming = false
        for index in rawLines.indices {
            let raw = rawLines[index]
            let lineEnd = index + 1 < rawLines.count ? max(raw.start, rawLines[index + 1].start) : raw.start + 4
            let lineWords = WordTiming.splitWords(raw.text)
            let taggedWords = raw.wordSegments.flatMap { WordTiming.splitWords($0.text) }
            let completeTags = !raw.wordSegments.isEmpty && taggedWords.count == lineWords.count
            let words: [LyricWord]
            if completeTags {
                var timed: [LyricWord] = []
                for segmentIndex in raw.wordSegments.indices {
                    let segment = raw.wordSegments[segmentIndex]
                    let segmentStart = max(raw.start, min(lineEnd, segment.start ?? raw.start))
                    let nextSegmentStart = segmentIndex + 1 < raw.wordSegments.count ? raw.wordSegments[segmentIndex + 1].start : nil
                    let segmentEnd = max(segmentStart, min(lineEnd, nextSegmentStart ?? lineEnd))
                    let tokens = WordTiming.splitWords(segment.text)
                    if tokens.count == 1 {
                        timed.append(LyricWord(text: tokens[0], start: segmentStart, end: max(segmentStart, segmentEnd)))
                    } else {
                        timed.append(contentsOf: WordTiming.estimate(words: tokens, start: segmentStart, end: segmentEnd))
                    }
                }
                words = timed
                hasWordTiming = true
            } else {
                words = WordTiming.estimate(words: lineWords, start: raw.start, end: lineEnd)
            }
            lines.append(LyricLine(start: raw.start, end: lineEnd, words: words))
        }
        return TrackLyrics(lines: lines, source: source, hasWordTiming: hasWordTiming, plainText: rawLines.map(\.text).joined(separator: "\n"))
    }

    static func parseNetEaseYRC(_ text: String) -> TrackLyrics? {
        struct Raw { var start: TimeInterval; var words: [LyricWord] }
        let lineRegex = try! NSRegularExpression(pattern: #"^\[(\d+),\d+\](.*)$"#)
        let wordRegex = try! NSRegularExpression(pattern: #"\((\d+),(\d+)\)([^()]*)"#)
        var raw: [Raw] = []
        for line in text.components(separatedBy: .newlines) {
            let range = NSRange(line.startIndex..., in: line)
            guard let header = lineRegex.firstMatch(in: line, range: range), let a = Range(header.range(at: 1), in: line), let lineStart = Double(String(line[a])) else { continue }
            let body = Range(header.range(at: 2), in: line).map { String(line[$0]) } ?? ""
            var words: [LyricWord] = []
            for match in wordRegex.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
                guard let sa = Range(match.range(at: 1), in: body), let da = Range(match.range(at: 2), in: body), let ta = Range(match.range(at: 3), in: body), let start = Double(String(body[sa])), let duration = Double(String(body[da])) else { continue }
                let tokens = WordTiming.splitWords(String(body[ta])); let begin = start / 1000; let end = begin + duration / 1000
                words.append(contentsOf: tokens.count == 1 ? [LyricWord(text: tokens[0], start: begin, end: end)] : WordTiming.estimate(words: tokens, start: begin, end: end))
            }
            if !words.isEmpty { raw.append(Raw(start: lineStart / 1000, words: words)) }
        }
        guard !raw.isEmpty else { return nil }
        raw.sort { $0.start < $1.start }
        let lines = raw.indices.map { index -> LyricLine in
            let end = index + 1 < raw.count ? max(raw[index].start, raw[index + 1].start) : (raw[index].words.last?.end ?? raw[index].start + 4)
            let words = raw[index].words.map { LyricWord(text: $0.text, start: max(raw[index].start, $0.start), end: min(end, max($0.start, $0.end))) }
            return LyricLine(start: raw[index].start, end: end, words: words)
        }
        return TrackLyrics(lines: lines, source: .netease, hasWordTiming: true, plainText: lines.map { $0.words.map { $0.text }.joined(separator: " ") }.joined(separator: "\n"))
    }

    static func parseTTML(_ data: Data, source: LyricsSource = .imported) -> TrackLyrics {
        let delegate = TTMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), !delegate.lines.isEmpty else {
            return TrackLyrics(lines: [], source: source, hasWordTiming: false, plainText: "")
        }

        let rawLines = delegate.lines.sorted { $0.start < $1.start }
        var output: [LyricLine] = []
        var hasWordTiming = false
        for index in rawLines.indices {
            let raw = rawLines[index]
            let lineEnd: TimeInterval
            if let explicitEnd = raw.end, explicitEnd > raw.start {
                lineEnd = explicitEnd
            } else if index + 1 < rawLines.count {
                lineEnd = max(raw.start, rawLines[index + 1].start)
            } else {
                lineEnd = raw.start + 4
            }
            let lineTokens = WordTiming.splitWords(raw.text)
            let segmentTokens = raw.segments.flatMap { WordTiming.splitWords($0.text) }
            let hasCompleteTiming = !raw.segments.isEmpty && segmentTokens.count == lineTokens.count && raw.segments.allSatisfy { $0.start != nil && $0.end != nil }
            let words: [LyricWord]
            if hasCompleteTiming {
                var timed: [LyricWord] = []
                for segment in raw.segments {
                    let start = max(raw.start, min(lineEnd, segment.start ?? raw.start))
                    let end = max(start, min(lineEnd, segment.end ?? lineEnd))
                    let tokens = WordTiming.splitWords(segment.text)
                    if tokens.count == 1 {
                        timed.append(LyricWord(text: tokens[0], start: start, end: end))
                    } else {
                        timed.append(contentsOf: WordTiming.estimate(words: tokens, start: start, end: end))
                    }
                }
                words = timed
                hasWordTiming = true
            } else {
                words = WordTiming.estimate(words: lineTokens, start: raw.start, end: lineEnd)
            }
            output.append(LyricLine(start: raw.start, end: lineEnd, words: words))
        }
        return TrackLyrics(lines: output, source: source, hasWordTiming: hasWordTiming, plainText: rawLines.map(\.text).joined(separator: "\n"))
    }

    private static func timestamp(from match: NSTextCheckingResult, in text: String) -> TimeInterval? {
        guard let minuteRange = Range(match.range(at: 1), in: text),
              let secondRange = Range(match.range(at: 2), in: text),
              let minutes = Double(String(text[minuteRange])),
              let seconds = Double(String(text[secondRange])) else { return nil }
        var fraction = 0.0
        if match.numberOfRanges > 3, let fractionRange = Range(match.range(at: 3), in: text) {
            fraction = Double("0." + String(text[fractionRange])) ?? 0
        }
        return minutes * 60 + seconds + fraction
    }

    private static func parseClock(_ value: String?) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if value.hasSuffix("s"), let seconds = Double(String(value.dropLast())) { return seconds }
        let components = value.split(separator: ":", omittingEmptySubsequences: false)
        if components.count == 2, let minutes = Double(String(components[0])), let seconds = Double(String(components[1])) {
            return minutes * 60 + seconds
        }
        if components.count == 3, let hours = Double(String(components[0])), let minutes = Double(String(components[1])), let seconds = Double(String(components[2])) {
            return hours * 3600 + minutes * 60 + seconds
        }
        return Double(value)
    }

    private final class TTMLParserDelegate: NSObject, XMLParserDelegate {
        var lines: [RawTTMLLine] = []
        private var inParagraph = false
        private var paragraphStart: TimeInterval?
        private var paragraphEnd: TimeInterval?
        private var paragraphText = ""
        private var spanStack: [TTMLSpan] = []
        private var wordSegments: [RawWordSegment] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let name = (qName ?? elementName).split(separator: ":").last.map(String.init)?.lowercased() ?? elementName.lowercased()
            if name == "p" {
                inParagraph = true
                paragraphStart = LyricsParser.parseClock(attribute("begin", in: attributeDict))
                paragraphEnd = LyricsParser.parseClock(attribute("end", in: attributeDict))
                paragraphText = ""
                spanStack = []
                wordSegments = []
            } else if name == "span", inParagraph {
                if !spanStack.isEmpty { spanStack[spanStack.count - 1].hasChild = true }
                spanStack.append(TTMLSpan(start: LyricsParser.parseClock(attribute("begin", in: attributeDict)), end: LyricsParser.parseClock(attribute("end", in: attributeDict))))
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard inParagraph else { return }
            paragraphText += string
            if !spanStack.isEmpty { spanStack[spanStack.count - 1].text += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let name = (qName ?? elementName).split(separator: ":").last.map(String.init)?.lowercased() ?? elementName.lowercased()
            if name == "span", inParagraph, !spanStack.isEmpty {
                let span = spanStack.removeLast()
                if !span.hasChild {
                    wordSegments.append(RawWordSegment(text: span.text, start: span.start, end: span.end))
                }
                if !spanStack.isEmpty { spanStack[spanStack.count - 1].text += span.text }
            } else if name == "p", inParagraph {
                if let start = paragraphStart {
                    lines.append(RawTTMLLine(start: start, end: paragraphEnd, text: paragraphText.trimmingCharacters(in: .whitespacesAndNewlines), segments: wordSegments))
                }
                inParagraph = false
                paragraphStart = nil
                paragraphEnd = nil
                paragraphText = ""
                spanStack = []
                wordSegments = []
            }
        }

        private func attribute(_ name: String, in values: [String: String]) -> String? {
            values.first { pair in
                pair.key.lowercased().split(separator: ":").last.map(String.init) == name
            }?.value
        }
    }
}
