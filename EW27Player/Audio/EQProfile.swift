import Foundation
import AVFoundation

struct EQFilter: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case parametric, lowShelf, highShelf }
    var id = UUID()
    var kind: Kind
    var frequency: Float
    var gain: Float
    var bandwidth: Float
}

struct EQProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var preamp: Float
    var filters: [EQFilter]
}

enum EQProfileStore {
    static let key = "ew27.eq.profiles.v1"

    static func load() -> [EQProfile] {
        guard let data = UserDefaults.standard.data(forKey: key), let profiles = try? JSONDecoder().decode([EQProfile].self, from: data) else { return [] }
        return profiles
    }

    static func save(_ profiles: [EQProfile]) {
        if let data = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(data, forKey: key) }
    }
}

enum AutoEQParser {
    static func parse(_ text: String, name: String) -> EQProfile? {
        var preamp: Float = 0
        var filters: [EQFilter] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.lowercased().hasPrefix("preamp:") {
                preamp = number(after: "preamp:", in: line) ?? 0
                continue
            }
            let upper = line.uppercased()
            guard !upper.contains(" OFF "), upper.contains(" ON "), filters.count < 16 else { continue }
            let kind: EQFilter.Kind
            if upper.contains(" LSC ") { kind = .lowShelf }
            else if upper.contains(" HSC ") { kind = .highShelf }
            else if upper.contains(" PK ") { kind = .parametric }
            else { continue }
            guard let frequency = number(after: "FC", in: upper), let gain = number(after: "GAIN", in: upper), let q = number(after: "Q", in: upper) else { continue }
            let bandwidth = max(0.05, min(5, (2 / log(2)) * asinh(1 / (2 * max(0.01, q)))))
            filters.append(EQFilter(kind: kind, frequency: max(20, min(20000, frequency)), gain: max(-24, min(24, gain)), bandwidth: bandwidth))
        }
        return filters.isEmpty && preamp == 0 ? nil : EQProfile(name: name, preamp: max(-24, min(24, preamp)), filters: filters)
    }

    private static func number(after token: String, in line: String) -> Float? {
        guard let range = line.range(of: token, options: [.caseInsensitive]) else { return nil }
        let tail = line[range.upperBound...]
        let pattern = #"[-+]?\d+(?:\.\d+)?"#
        guard let match = tail.range(of: pattern, options: .regularExpression) else { return nil }
        return Float(tail[match])
    }
}
