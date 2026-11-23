import Foundation

/// Refuses offensive pseudos. The same lists guard the server (firestore.rules `cleanName`),
/// so a modified app cannot publish one either.
public enum NameFilter {
    /// Refused anywhere in the pseudo.
    static let anywhere = ["putain", "salope", "salaud", "encul", "niquer", "niquetamere", "niktamer", "connard", "connasse", "conasse",
                           "batard", "merde", "couille", "pedophile", "pedo", "hitler", "negre", "bougnoul", "youpin", "bicot",
                           "tapette", "tafiole", "gouine", "porno", "sexe", "fuck", "shit", "bitch", "cunt", "nigg", "whore", "slut",
                           "enfoir", "filsdepute", "fdp", "daech"]
    /// Refused only as the whole pseudo: too common inside ordinary names (Computer, Monique, Nazim).
    static let whole = ["pute", "lapute", "con", "lecon", "nazi", "bite", "pd", "ntm", "nique", "pede", "viol", "suce", "sucemoi"]

    /// The pseudo a new player gets at first launch, until they choose one in Profil ("Joueur4821").
    public static func automatic() -> String { "Joueur\(Int.random(in: 1000...99999))" }
    /// True for a pseudo given automatically: the player has not chosen one yet.
    public static func isAutomatic(_ name: String) -> Bool {
        name.hasPrefix("Joueur") && (4...5).contains(name.count - 6) && name.dropFirst(6).allSatisfy { $0.isASCII && $0.isNumber }
    }

    public static func isAllowed(_ name: String) -> Bool {
        let key = simplified(name)
        return !whole.contains(key) && !anywhere.contains { key.contains($0) }
    }
    /// Lower case letters only, accents dropped and look-alike digits read as letters.
    static func simplified(_ name: String) -> String {
        let leet: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s"]
        return String(name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased().compactMap { character -> Character? in
                if let letter = leet[character] { return letter }
                return character.isASCII && character.isLetter ? character : nil
            })
    }
}
