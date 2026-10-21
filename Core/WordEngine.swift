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
