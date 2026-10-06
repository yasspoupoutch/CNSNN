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
    public static func matches(_ answer: String, word: String) -> Bool {
        let normalized = normalize(answer)
        return !normalized.isEmpty && normalized == normalize(word)
    }
    public static func validWord(_ word: String) -> Bool {
        let full = normalize(word)
        return (3...40).contains(full.count) && !consonants(word).isEmpty
    }
}
