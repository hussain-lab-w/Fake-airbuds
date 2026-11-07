import Foundation

struct LyricsProviderClient {
    struct Result {
        let lyrics: TrackLyrics
        let definitiveMiss: Bool
    }

    static func lookup(title: String, artist: String, album: String, duration: Int) async -> [Result] {
        await withTaskGroup(of: Result?.self, returning: [Result].self) { group in
            group.addTask { await netease(title: title, artist: artist, duration: duration) }
            group.addTask { await appleMusic(title: title, artist: artist, duration: duration) }
            group.addTask { await lyricsOvh(title: title, artist: artist) }
            var results: [Result] = []
            for await result in group {
                if let result { results.append(result) }
            }
            return results
        }
    }

    private static func netease(title: String, artist: String, duration: Int) async -> Result? {
        guard var components = URLComponents(string: "https://music.163.com/api/search/get/web") else { return nil }
        components.queryItems = [URLQueryItem(name: "s", value: "\(artist) \(title)"), URLQueryItem(name: "type", value: "1"), URLQueryItem(name: "limit", value: "8")]
        guard let url = components.url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let search = try JSONDecoder().decode(NetEaseSearchResponse.self, from: data)
            let song = search.result.songs
                .filter { abs(Double($0.duration / 1000) - Double(duration)) <= 8 || duration == 0 }
                .min { abs(Double($0.duration / 1000) - Double(duration)) < abs(Double($1.duration / 1000) - Double(duration)) } ?? search.result.songs.first
            guard let song else { return nil }
            var lyricComponents = URLComponents(string: "https://music.163.com/api/song/lyric")!
            lyricComponents.queryItems = [URLQueryItem(name: "id", value: String(song.id)), URLQueryItem(name: "lv", value: "-1"), URLQueryItem(name: "kv", value: "-1"), URLQueryItem(name: "tv", value: "-1")]
            guard let lyricURL = lyricComponents.url else { return nil }
            let (lyricData, lyricResponse) = try await URLSession.shared.data(from: lyricURL)
            guard (lyricResponse as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let lyrics = try JSONDecoder().decode(NetEaseLyricResponse.self, from: lyricData)
            if let yrc = lyrics.yrc?.lyric, let parsed = LyricsParser.parseNetEaseYRC(yrc), parsed.hasWordTiming { return Result(lyrics: parsed, definitiveMiss: false) }
            if let lrc = lyrics.lrc?.lyric, !lrc.isEmpty { return Result(lyrics: LyricsParser.parseLRC(lrc, source: .netease), definitiveMiss: false) }
        } catch is CancellationError {
            return nil
        } catch { }
        return nil
    }


    private static func appleMusic(title: String, artist: String, duration: Int) async -> Result? {
        guard let lyrics = await AppleMusicLyricsProvider.lookup(title: title, artist: artist, duration: duration) else { return nil }
        return Result(lyrics: lyrics, definitiveMiss: false)
    }

    private static func lyricsOvh(title: String, artist: String) async -> Result? {
        let artistPart = artist.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? artist
        let titlePart = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        guard let url = URL(string: "https://api.lyrics.ovh/v1/\(artistPart)/\(titlePart)") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let result = try JSONDecoder().decode(LyricsOvhResponse.self, from: data)
            guard !result.lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return Result(lyrics: LyricsParser.parse(result.lyrics, source: .lyricsOvh), definitiveMiss: false)
        } catch { return nil }
    }
}

private struct NetEaseSearchResponse: Decodable {
    struct Payload: Decodable {
        var songs: [Song]
        struct Song: Decodable { var id: Int; var duration: Int }
    }
    var result: Payload
}

private struct NetEaseLyricResponse: Decodable {
    struct Lyric: Decodable { var lyric: String? }
    var lrc: Lyric?
    var yrc: Lyric?
}

private struct LyricsOvhResponse: Decodable { var lyrics: String }
