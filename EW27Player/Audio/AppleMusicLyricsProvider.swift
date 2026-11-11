import Foundation

struct AppleMusicLyricsProvider {
    static func lookup(title: String, artist: String, duration: Int) async -> TrackLyrics? {
        guard let token = await token(), let songID = await songID(title: title, artist: artist, duration: duration, token: token) else { return nil }
        for endpoint in [
            "https://lyrics.paxsenix.org/apple-music/lyrics?id=\(songID)",
            "https://api.zarz.moe/apple-music/lyrics?id=\(songID)&v=1"
        ] {
            guard let url = URL(string: endpoint) else { continue }
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.setValue("EW27Player/1.0", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
                if let text = formatPayload(data), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let parsed = LyricsParser.parse(text, source: .appleMusic)
                    if parsed.isSynced || !parsed.plainText.isEmpty { return parsed }
                }
            } catch { }
        }
        return nil
    }

    private static func token() async -> String? {
        guard let pageURL = URL(string: "https://beta.music.apple.com") else { return nil }
        do {
            var pageRequest = URLRequest(url: pageURL, timeoutInterval: 20)
            pageRequest.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            let (pageData, _) = try await URLSession.shared.data(for: pageRequest)
            let html = String(decoding: pageData, as: UTF8.self)
            guard let scriptMatch = html.range(of: #"/assets/index~[^\"' <]+\.js"#, options: .regularExpression) else { return nil }
            guard let scriptURL = URL(string: "https://beta.music.apple.com" + String(html[scriptMatch])) else { return nil }
            var scriptRequest = URLRequest(url: scriptURL, timeoutInterval: 20)
            scriptRequest.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            let (scriptData, _) = try await URLSession.shared.data(for: scriptRequest)
            let script = String(decoding: scriptData, as: UTF8.self)
            guard let jwt = script.range(of: #"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#, options: .regularExpression) else { return nil }
            return String(script[jwt])
        } catch { return nil }
    }

    private static func songID(title: String, artist: String, duration: Int, token: String) async -> String? {
        var components = URLComponents(string: "https://amp-api.music.apple.com/v1/catalog/us/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: "\(title) \(artist)"),
            URLQueryItem(name: "types", value: "songs"),
            URLQueryItem(name: "limit", value: "25"),
            URLQueryItem(name: "l", value: "en-US"),
            URLQueryItem(name: "platform", value: "web"),
            URLQueryItem(name: "format[resources]", value: "map"),
            URLQueryItem(name: "include[songs]", value: "artists")
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.apple.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let results = root["results"] as? [String: Any], let songs = results["songs"] as? [String: Any], let values = songs["data"] as? [[String: Any]] else { return nil }
            let ranked = values.compactMap { value -> (String, Double)? in
                guard let id = value["id"] as? String, let attributes = value["attributes"] as? [String: Any], let name = attributes["name"] as? String, let songArtist = attributes["artistName"] as? String else { return nil }
                let ms = (attributes["durationInMillis"] as? NSNumber)?.doubleValue ?? 0
                let requestedTitle = normalized(title)
                let requestedArtist = normalized(artist)
                guard !requestedTitle.isEmpty else { return nil }
                let candidateTitle = normalized(name)
                let titleScore = candidateTitle == requestedTitle ? 2 : (candidateTitle.contains(requestedTitle) ? 1 : 0)
                let artistScore = requestedArtist.isEmpty || normalized(songArtist).contains(requestedArtist) ? 2 : 0
                let durationDifference = ms > 0 ? abs(ms / 1000 - Double(duration)) : 0
                guard titleScore > 0, artistScore > 0, duration <= 0 || ms <= 0 || durationDifference <= 8 else { return nil }
                let durationScore = duration > 0 && ms > 0 ? max(0, 1 - durationDifference / 10) : 0
                return (id, Double(titleScore + artistScore) + durationScore)
            }
            return ranked.max { $0.1 < $1.1 }?.0
        } catch { return nil }
    }

    private static func formatPayload(_ data: Data) -> String? {
        if let raw = String(data: data, encoding: .utf8), raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") { return raw }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let string = object as? String { return string }
        guard let dictionary = object as? [String: Any] else { return nil }
        for key in ["elrc", "lrc", "lyrics", "lyrics_text", "plain", "plainLyrics", "ttml", "ttml_content"] {
            if let value = dictionary[key] as? String, !value.isEmpty { return value }
        }
        guard let content = dictionary["content"] as? [[String: Any]] else { return nil }
        var output: [String] = []
        for line in content {
            guard let timestamp = number(line["timestamp"]), let details = line["text"] as? [[String: Any]] else { continue }
            var value = "[\(lrcTime(timestamp))]"
            for detail in details {
                if let start = number(detail["timestamp"]) { value += "<\(lrcTime(start))>" }
                value += detail["text"] as? String ?? ""
                if let end = number(detail["endtime"]) { value += "<\(lrcTime(end))>" }
                if (detail["part"] as? Bool) != true { value += " " }
            }
            output.append(value.trimmingCharacters(in: .whitespaces))
        }
        return output.joined(separator: "\n")
    }

    private static func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
    private static func lrcTime(_ milliseconds: Double) -> String { String(format: "%02d:%05.2f", Int(milliseconds / 60000), (milliseconds.truncatingRemainder(dividingBy: 60000)) / 1000) }
    private static func normalized(_ value: String) -> String { value.lowercased().folding(options: .diacriticInsensitive, locale: .current).components(separatedBy: CharacterSet.alphanumerics.inverted).joined() }
}
