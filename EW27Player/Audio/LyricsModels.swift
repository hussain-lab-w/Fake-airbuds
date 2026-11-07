import Foundation

struct LyricWord: Codable, Equatable {
    var text: String
    var start: TimeInterval
    var end: TimeInterval
}

struct LyricLine: Codable, Equatable {
    var start: TimeInterval
    var end: TimeInterval
    var words: [LyricWord]
}

enum LyricsSource: String, Codable {
    case embeddedPlain
    case lrclib
    case netease
    case lyricsOvh
    case imported
}

struct TrackLyrics: Codable, Equatable {
    var lines: [LyricLine]
    var source: LyricsSource
    var hasWordTiming: Bool
    var plainText: String

    var isSynced: Bool { !lines.isEmpty }
}
