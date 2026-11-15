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
        let steps = total < 2 ? [] : (1..<total).map { k -> String in
            var seen = 0
            return String(letters.filter { c in
                guard "AEIOUY".contains(c) else { return true }
                seen += 1; return seen <= k
            })
        }
        return (max(total, 1), steps)
    }
    /// What the board shows: the consonants of each word, a space between words (a hyphen splits them too), a dash for a word
    /// with no consonant (« Où est Charlie » is « – ST CHRL »). A single word is just its consonants.
    public static func shownConsonants(_ value: String) -> String {
        let words = value.split(whereSeparator: { $0.isWhitespace || "-‐‑–—".contains($0) }).map(String.init).filter { !normalize($0).isEmpty }
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
