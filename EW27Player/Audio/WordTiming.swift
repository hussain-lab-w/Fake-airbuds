import Foundation

enum WordTiming {
    static func splitWords(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    static func estimate(words: [String], start: TimeInterval, end: TimeInterval) -> [LyricWord] {
        guard !words.isEmpty else { return [] }
        let duration = max(0, end - start)
        let weights = words.map { word -> Double in
            let characters = Double(word.reduce(into: 0) { count, character in
                if !character.isWhitespace { count += 1 }
            })
            let punctuation: Set<Character> = [",", ".", "!", "?"]
            return max(1, characters + (word.last.map { punctuation.contains($0) } == true ? 0.35 : 0))
        }
        let weightTotal = max(1, weights.reduce(0, +))
        let minimum = 0.08
        let canUseMinimum = duration >= minimum * Double(words.count)
        let remaining = canUseMinimum ? duration - minimum * Double(words.count) : duration
        let allocations = weights.map { weight in
            (canUseMinimum ? minimum : 0) + remaining * weight / weightTotal
        }

        var cursor = start
        return words.enumerated().map { index, word in
            let wordEnd = index == words.count - 1 ? end : min(end, cursor + allocations[index])
            let result = LyricWord(text: word, start: cursor, end: max(cursor, wordEnd))
            cursor = result.end
            return result
        }
    }
}
