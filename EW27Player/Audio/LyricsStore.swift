import Foundation
import MediaPlayer
import Combine

@MainActor
final class LyricsStore: ObservableObject {
    @Published private(set) var lyrics: TrackLyrics?
    @Published private(set) var isLoading = false
    @Published private(set) var currentTrackID: UInt64?
    @Published private(set) var syncOffset: TimeInterval = 0

    static let onlineLookupKey = "ew27.lyrics.onlineLookup"
    private let fileManager = FileManager.default
    private var lookupTask: Task<Void, Never>?
    private var currentItem: MPMediaItem?
    private var currentDuration: TimeInterval = 0
    private var memoryCache: [UInt64: TrackLyrics] = [:]

    init() {
        UserDefaults.standard.register(defaults: [Self.onlineLookupKey: true])
    }

    func load(for item: MPMediaItem, duration: TimeInterval, force: Bool = false) {
        let id = item.persistentID
        guard force || currentTrackID != id else { return }
        lookupTask?.cancel()
        lookupTask = nil
        currentItem = item
        currentDuration = duration
        currentTrackID = id
        syncOffset = UserDefaults.standard.double(forKey: offsetKey(for: id))
        isLoading = false
        lyrics = nil

        if let imported = readImportedLyrics(for: id) {
            lyrics = MornyeLyricsTiming.normalized(imported)
            return
        }
        if !force {
            if let cachedLyrics = memoryCache[id] {
                lyrics = MornyeLyricsTiming.normalized(cachedLyrics)
                return
            }
            if let cache = readCache(for: id) {
                if let cachedLyrics = cache.lyrics {
                    let normalized = MornyeLyricsTiming.normalized(cachedLyrics)
                    memoryCache[id] = normalized
                    lyrics = normalized
                    return
                }
                if let missUntil = cache.missUntil, missUntil > Date() {
                    lyrics = embeddedLyrics(for: item)
                    return
                }
            }
        }
        guard UserDefaults.standard.bool(forKey: Self.onlineLookupKey) else {
            lyrics = embeddedLyrics(for: item)
            return
        }
        startLookup(for: item, duration: duration)
    }

    func onlineLookupSettingChanged(_ enabled: Bool) {
        if !enabled {
            lookupTask?.cancel()
            lookupTask = nil
            isLoading = false
            if let currentItem, lyrics == nil {
                lyrics = embeddedLyrics(for: currentItem)
            }
            return
        }
        guard let currentItem, lyrics?.source != .imported else { return }
        load(for: currentItem, duration: currentDuration, force: true)
    }

    func adjustSyncOffset(by delta: TimeInterval) {
        syncOffset += delta
        guard let currentTrackID else { return }
        UserDefaults.standard.set(syncOffset, forKey: offsetKey(for: currentTrackID))
    }

    func importLyrics(_ imported: TrackLyrics, for persistentID: UInt64) {
        var lyrics = imported
        lyrics.source = .imported
        do {
            let directory = lyricsDirectory()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(lyrics)
            try data.write(to: importedURL(for: persistentID), options: .atomic)
        } catch {
            return
        }
        guard currentTrackID == persistentID else { return }
        memoryCache[persistentID] = lyrics
        lookupTask?.cancel()
        lookupTask = nil
        isLoading = false
        self.lyrics = lyrics
    }

    private func startLookup(for item: MPMediaItem, duration: TimeInterval) {
        isLoading = true
        let title = item.title ?? ""
        let artist = item.artist ?? ""
        let album = item.albumTitle ?? ""
        let roundedDuration = Int(duration.rounded())
        let id = item.persistentID
        lookupTask = Task { [weak self] in
            guard let self else { return }
            async let lrclibSearch = self.lookupLRCLIB(title: title, artist: artist, album: album, duration: roundedDuration)
            let additional = await LyricsProviderClient.lookup(title: title, artist: artist, album: album, duration: roundedDuration)
            let lrclib: (lyrics: TrackLyrics?, definitiveMiss: Bool)
            if additional.contains(where: { $0.lyrics.hasWordTiming }) {
                lrclib = (nil, false)
            } else {
                lrclib = await lrclibSearch
            }
            guard !Task.isCancelled, self.currentTrackID == id else { return }
            let candidates = additional.map(\.lyrics) + (lrclib.lyrics.map { [$0] } ?? [])
            let found = candidates.first(where: { $0.hasWordTiming }) ?? candidates.first(where: { $0.isSynced }) ?? candidates.first
            if let found {
                let normalized = MornyeLyricsTiming.normalized(found)
                self.memoryCache[id] = normalized
                self.writeCache(LyricsCache(lyrics: normalized, missUntil: nil), for: id)
                self.lyrics = normalized
            } else {
                if lrclib.definitiveMiss {
                    self.writeCache(LyricsCache(lyrics: nil, missUntil: Date().addingTimeInterval(7 * 24 * 60 * 60)), for: id)
                }
                self.lyrics = self.embeddedLyrics(for: item)
            }
            self.isLoading = false
            self.lookupTask = nil
        }
    }

    private func lookupLRCLIB(title: String, artist: String, album: String, duration: Int) async -> (lyrics: TrackLyrics?, definitiveMiss: Bool) {
        var queryItems = [URLQueryItem(name: "track_name", value: title)]
        if !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "artist_name", value: artist))
        }
        if !album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "album_name", value: album))
        }
        if duration > 0 { queryItems.append(URLQueryItem(name: "duration", value: String(duration))) }
        if artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return await searchLRCLIB(title: title, artist: artist, duration: duration)
        }
        guard let getURL = makeURL(path: "/api/get", items: queryItems) else { return (nil, false) }
        do {
            let (data, response) = try await request(getURL)
            guard let http = response as? HTTPURLResponse else { return (nil, false) }
            if http.statusCode == 404 {
                return await searchLRCLIB(title: title, artist: artist, duration: duration)
            }
            guard http.statusCode == 200 else { return (nil, false) }
            let result = try JSONDecoder().decode(LRCLibTrack.self, from: data)
            if result.hasWordSync == true,
               let lyricsfile = result.lyricsfile,
               !lyricsfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let parsed = LyricsParser.parseLyricsfile(lyricsfile, source: .lrclib)
                if parsed.hasWordTiming { return (parsed, false) }
            }
            if let synced = result.syncedLyrics, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (LyricsParser.parseLRC(synced, source: .lrclib), false)
            }
            if let plain = result.plainLyrics, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (LyricsParser.parse(plain, source: .lrclib), false)
            }
            return (nil, true)
        } catch is CancellationError {
            return (nil, false)
        } catch {
            return (nil, false)
        }
    }

    private func searchLRCLIB(title: String, artist: String, duration: Int) async -> (lyrics: TrackLyrics?, definitiveMiss: Bool) {
        var queryItems = [URLQueryItem(name: "track_name", value: title)]
        if !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "artist_name", value: artist))
        }
        guard let searchURL = makeURL(path: "/api/search", items: queryItems) else { return (nil, false) }
        do {
            let (data, response) = try await request(searchURL)
            guard let http = response as? HTTPURLResponse else { return (nil, false) }
            if http.statusCode == 404 { return (nil, true) }
            guard http.statusCode == 200 else { return (nil, false) }
            let results = try JSONDecoder().decode([LRCLibTrack].self, from: data)
            let matching = results
                .filter { abs($0.duration - Double(duration)) <= 2 }
                .sorted { abs($0.duration - Double(duration)) < abs($1.duration - Double(duration)) }
            for candidate in matching where candidate.hasWordSync == true {
                guard let lyricsfile = candidate.lyricsfile else { continue }
                let parsed = LyricsParser.parseLyricsfile(lyricsfile, source: .lrclib)
                if parsed.hasWordTiming { return (parsed, false) }
            }
            if let synced = matching.first(where: { $0.syncedLyrics?.isEmpty == false })?.syncedLyrics {
                return (LyricsParser.parseLRC(synced, source: .lrclib), false)
            }
            return (nil, true)
        } catch is CancellationError {
            return (nil, false)
        } catch {
            return (nil, false)
        }
    }

    private func request(_ url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("EW27Player/2.2 (https://github.com/hussain-lab-w/Fake-airbuds)", forHTTPHeaderField: "User-Agent")
        return try await URLSession.shared.data(for: request)
    }

    private func makeURL(path: String, items: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: "https://lrclib.net\(path)")
        components?.queryItems = items
        return components?.url
    }

    private func embeddedLyrics(for item: MPMediaItem) -> TrackLyrics? {
        guard let text = item.lyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return TrackLyrics(lines: [], source: .embeddedPlain, hasWordTiming: false, plainText: text)
    }

    private func lyricsDirectory() -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        return support.appendingPathComponent("lyrics", isDirectory: true)
    }

    private func importedURL(for id: UInt64) -> URL {
        lyricsDirectory().appendingPathComponent("\(id).json")
    }

    private func cacheURL(for id: UInt64) -> URL {
        lyricsDirectory().appendingPathComponent("lrclib-cache-v2", isDirectory: true).appendingPathComponent("\(id).json")
    }

    private func readImportedLyrics(for id: UInt64) -> TrackLyrics? {
        guard let data = try? Data(contentsOf: importedURL(for: id)), var imported = try? JSONDecoder().decode(TrackLyrics.self, from: data) else { return nil }
        imported.source = .imported
        return imported
    }

    private func readCache(for id: UInt64) -> LyricsCache? {
        guard let data = try? Data(contentsOf: cacheURL(for: id)) else { return nil }
        return try? JSONDecoder().decode(LyricsCache.self, from: data)
    }

    private func writeCache(_ cache: LyricsCache, for id: UInt64) {
        if let cachedLyrics = cache.lyrics {
            memoryCache[id] = MornyeLyricsTiming.normalized(cachedLyrics)
        }
        do {
            let url = cacheURL(for: id)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(cache).write(to: url, options: .atomic)
        } catch { }
    }

    private func offsetKey(for id: UInt64) -> String { "ew27.lyrics.offset.\(id)" }
}

private struct LyricsCache: Codable {
    var lyrics: TrackLyrics?
    var missUntil: Date?
}

private struct LRCLibTrack: Decodable {
    var syncedLyrics: String?
    var plainLyrics: String?
    var lyricsfile: String?
    var hasWordSync: Bool?
    var duration: Double
}
