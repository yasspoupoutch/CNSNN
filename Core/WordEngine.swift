import Foundation

public enum WordEngine {
    /// French editorial convention: Y is a vowel, Œ and Æ expand before filtering.
    public static func normalize(_ value: String) -> String {
        value.replacingOccurrences(of: "œ", with: "oe").replacingOccurrences(of: "Œ", with: "OE")
            .replacingOccurrences(of: "æ", with: "ae").replacingOccurrences(of: "Æ", with: "AE")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .uppercased(with: Locale(identifier: "fr_FR"))
            .filter { $0.isASCII && $0.isLetter }
    }
    public static func consonants(_ value: String) -> String {
        normalize(value).filter { !"AEIOUY".contains($0) }
    }
    /// The vowels of the word, each once, in alphabetical order: the first hint lights them up on the keyboard.
    public static func vowels(_ value: String) -> String {
        let present = Set(normalize(value).filter { "AEIOUY".contains($0) })
        return String("AEIOUY".filter(present.contains))
    }
    /// The hints after the sentence place the word's vowels one by one, in order (ŒUVRE: OVR, OEVR, OEUVR).
    /// `letters` counts the vowels; the last one is the word itself, revealed at the end, so the steps
    /// stop one before (same as Firebase/tools/daily.mjs placedVowels).
    public static func placedVowels(_ value: String) -> (letters: Int, steps: [String]) {
        let letters = Array(normalize(value))
        let total = letters.filter { "AEIOUY".contains($0) }.count
        // An expression keeps its words apart, like the board (« QUST C QN – FT – BN DN »), so it can go on several lines.
        let words = boardWords(value)
        let steps = total < 2 ? [] : (1..<total).map { k -> String in
            var seen = 0
            let keep: (Character) -> Bool = { c in
                guard "AEIOUY".contains(c) else { return true }
                seen += 1; return seen <= k
            }
            guard words.count > 1 else { return String(letters.filter(keep)) }
            return words.map { word -> String in
                let placed = String(normalize(word).filter(keep))
                return placed.isEmpty ? "–" : placed
            }.joined(separator: " ")
        }
        return (max(total, 1), steps)
    }
    private static func boardWords(_ value: String) -> [String] {
        value.split(whereSeparator: { $0.isWhitespace || "-‐‑–—".contains($0) }).map(String.init).filter { !normalize($0).isEmpty }
    }
    /// A board (or an expression) cut on its spaces into as few lines as possible, at most `maxLines`, each line
    /// `maxChars` long at most when it can be, the lines as even as they can be. A single word stays on one line
    /// (the screen shrinks it instead). « QST C QN – FT – BN DN » is « QST C QN », « – FT – », « BN DN ».
    public static func lines(_ text: String, maxChars: Int = 10, maxLines: Int = 3) -> [String] {
        let words = text.split(separator: " ").map(String.init)
        guard words.count > 1, text.count > maxChars else { return [text] }
        func cuts(_ start: Int, _ left: Int) -> [[Int]] {
            guard left > 1 else { return [[]] }
            return (start + 1...words.count - left + 1).flatMap { cut in cuts(cut, left - 1).map { [cut] + $0 } }
        }
        var best: [String] = [text]
        var bestWidest = Int.max
        // Every way to cut the words into n lines, from one line up: the first n whose lines all fit wins,
        // the most even one among them; if none fits, the most even with the most lines allowed.
        let most = min(maxLines, words.count)
        for n in 1...most {
            bestWidest = Int.max
            for cut in cuts(0, n) {
                let bounds = [0] + cut + [words.count]
                let split = zip(bounds, bounds.dropFirst()).map { words[$0..<$1].joined(separator: " ") }
                let widest = split.map(\.count).max() ?? 0
                if widest < bestWidest { best = split; bestWidest = widest }
            }
            if bestWidest <= maxChars { break }
        }
        return best
    }
    /// What the board shows: the consonants of each word, a space between words (a hyphen splits them too), a dash for a word
    /// with no consonant (« Où est Charlie » is « – ST CHRL »). A single word is just its consonants.
    public static func shownConsonants(_ value: String) -> String {
        let words = boardWords(value)
        guard words.count > 1 else { return consonants(value) }
        return words.map { consonants($0).isEmpty ? "–" : consonants($0) }.joined(separator: " ")
    }
    /// The board read aloud: letters apart, words apart.
    public static func spoken(_ shown: String) -> String {
        shown.split(separator: " ").map { $0.map(String.init).joined(separator: ", ") }.joined(separator: " ; ")
    }
    public static func matches(_ answer: String, word: String) -> Bool {
        let normalized = normalize(answer)
        return !normalized.isEmpty && normalized == normalize(word)
    }
    public static func validWord(_ word: String) -> Bool {
        let full = normalize(word)
        return (3...40).contains(full.count) && !consonants(word).isEmpty
    }
}

/// The answer being typed, with its caret: letters go in at the caret, ⌫ erases the letter before it,
/// and a slide on the space bar or on the answer itself moves it. `cursor` counts the characters before
/// the caret; nil keeps it at the end, where typing normally happens.
public struct TypedAnswer: Equatable {
    public static let maxLength = 40
    public var text: String
    public var cursor: Int?

    public init(text: String, cursor: Int? = nil) { self.text = text; self.cursor = cursor }

    /// Where the caret really is, even after the text was replaced behind its back.
    public var position: Int { min(max(cursor ?? text.count, 0), text.count) }
    public var before: String { String(text.prefix(position)) }
    public var after: String { String(text.dropFirst(position)) }
    /// The caret's place when it sits inside the text, nil when it is at the end.
    public var inside: Int? { position < text.count ? position : nil }

    /// No space at the start or next to another space, and 40 characters at most.
    public mutating func insert(_ letter: String) {
        guard text.count + letter.count <= Self.maxLength else { return }
        if letter == " ", before.isEmpty || before.hasSuffix(" ") || after.hasPrefix(" ") { return }
        let at = position
        text = before + letter + after
        place(at + letter.count)
    }

    public mutating func deleteBackward() {
        let at = position
        guard at > 0 else { return }
        text = String(text.prefix(at - 1)) + after
        place(at - 1)
    }

    /// Moves the caret by a number of characters, staying inside the text.
    public mutating func move(by steps: Int) { place(position + steps) }

    /// Puts the caret before character `index` (0 = start); past the end means at the end.
    public mutating func place(_ index: Int) {
        let clamped = min(max(index, 0), text.count)
        cursor = clamped == text.count ? nil : clamped
    }
}
