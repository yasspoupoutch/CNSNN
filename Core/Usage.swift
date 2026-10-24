import Foundation

/// Anonymous attendance (`stats/{day}`, read by the admins only): how many phones opened the app or
/// played that day, and the games of each mode. Nothing names the player or the phone: each phone
/// remembers here what it already counted and only ever sends increments (same as Android's Usage.kt).
public struct UsageTally: Codable, Equatable, Sendable {
    /// Counted without an account (a phone that has not chosen a pseudo yet).
    public static let openFields = ["opensIos", "opensAndroid", "newIos", "newAndroid"]
    /// Counted once signed in (see Firebase/firestore.rules).
    public static let playFields = ["players", "newPlayers", "daily", "classic", "sprint", "survival", "duo", "challenge"]

    /// Counts not sent yet, by day (yyyy-MM-dd on the phone's calendar) then field.
    public var pending: [String: [String: Int]] = [:]
    /// Last day this phone counted itself as opened, and as played.
    public var openedDay: String?
    public var playedDay: String?
    /// This phone was counted (or already used the app before the counter existed) and has played once.
    public var known = false
    public var played = false

    public init() {}

    /// The app is on screen. `platform` is "Ios" or "Android". `returning`: games or a pseudo already on
    /// this phone, so a player updating the app is not counted as a new download.
    public mutating func open(day: String, platform: String, returning: Bool) {
        if !known {
            known = true
            if returning { played = true } else { add("new" + platform, day: day) }
        }
        guard openedDay != day else { return }
        openedDay = day
        add("opens" + platform, day: day)
    }
    /// A game finished: `mode` is one of `playFields` after the first two.
    public mutating func play(_ mode: String, day: String) {
        guard Self.playFields.dropFirst(2).contains(mode) else { return }
        if playedDay != day {
            playedDay = day
            add("players", day: day)
            if !played { played = true; add("newPlayers", day: day) }
        }
        add(mode, day: day)
    }
    /// The counts to send, by day, removed from `pending`. Days before `oldest` are dropped (the server
    /// refuses them); without an account only the opening counts go, the rest waits for the sign-in.
    public mutating func take(oldest: String, signedIn: Bool) -> [String: [String: Int]] {
        pending = pending.filter { $0.key >= oldest }
        var sent: [String: [String: Int]] = [:]
        for (day, counts) in pending {
            let ready = counts.filter { signedIn || Self.openFields.contains($0.key) }
            guard !ready.isEmpty else { continue }
            sent[day] = ready
            let left = counts.filter { !ready.keys.contains($0.key) }
            pending[day] = left.isEmpty ? nil : left
        }
        return sent
    }
    private mutating func add(_ field: String, day: String) {
        pending[day, default: [:]][field, default: 0] += 1
    }
}
