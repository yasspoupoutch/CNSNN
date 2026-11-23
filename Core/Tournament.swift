import Foundation

// Tournoi de la semaine: everyone can sign up until Monday 9 h (Paris, winter time: 08:00 UTC). Then a
// knockout bracket, one round a day: each player of a match plays the same 5 words whenever they want
// within the 24 hours, the best time goes through (+20 s per word passed), the other one is out.
// No server: the bracket follows from the players signed up (a draw seeded by the week) and from the
// runs stamped by Firestore (tournaments/{week}/…, see Firebase/firestore.rules). Same as Tournament.kt.

public enum TournamentRules {
    public static let maxPlayers = 64
    /// From this tournament on, everyone plays every round: neighbours meet, and with an odd number the
    /// last match is played by 3 (the fastest goes through). Before: a full bracket of 2, 4, 8… with byes.
    /// A date, not a version: every phone must draw the same bracket.
    public static let everyonePlaysFrom = "2026-12-07"
    public static func everyonePlays(week: String) -> Bool { week >= everyonePlaysFrom }
    public static let dayMs = 86_400_000
    /// Sign-ups close, and the first round opens, on Monday at 08:00 UTC.
    public static let startHourMs = 8 * 3_600_000

    /// A week's id: its Monday, "2026-11-16".
    public static func deadlineMs(week: String) -> Int? {
        let parts = week.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        let day = daysFromCivil(parts[0], parts[1], parts[2])
        guard weekday(day) == 0 else { return nil }
        return day * dayMs + startHourMs
    }
    /// The tournament whose sign-ups are open now.
    public static func nextWeek(nowMs: Int) -> String {
        let day = floorDiv(nowMs - startHourMs, dayMs)
        var monday = day - weekday(day)
        if monday * dayMs + startHourMs <= nowMs { monday += 7 }
        return civil(monday)
    }
    /// The tournament under way (or just over): the one that started last Monday.
    public static func currentWeek(nowMs: Int) -> String {
        civil(floorDiv((deadlineMs(week: nextWeek(nowMs: nowMs)) ?? 0) - startHourMs, dayMs) - 7)
    }
    /// Round r (from 1) is open for 24 hours, the first one from the Monday deadline.
    public static func roundStartMs(week: String, round: Int) -> Int? { deadlineMs(week: week).map { $0 + (round - 1) * dayMs } }
    public static func roundEndMs(week: String, round: Int) -> Int? { deadlineMs(week: week).map { $0 + round * dayMs } }
    /// 2 players: 1 round (the final); up to 64: 6 rounds. Everyone playing (from `everyonePlaysFrom`):
    /// 3 players, one match of 3; 10 players, 5 matches, then 2 (one of 3), then the final.
    public static func rounds(players: Int, week: String = "") -> Int {
        let count = min(players, maxPlayers)
        guard count >= 2 else { return 0 }
        var size = 1, rounds = 0
        if everyonePlays(week: week) {
            while size * 2 <= count { size *= 2; rounds += 1 }
        } else {
            while size < count { size *= 2; rounds += 1 }
        }
        return rounds
    }
    /// The round open at this moment, if any.
    public static func round(week: String, players: Int, nowMs: Int) -> Int? {
        guard let start = deadlineMs(week: week), nowMs >= start else { return nil }
        let round = (nowMs - start) / dayMs + 1
        return round <= rounds(players: players, week: week) ? round : nil
    }
    /// The words of a round, drawn by the first player who starts it (then kept in Firestore).
    public static func draw(week: String, round: Int) -> [String] { ChallengeRules.draw(seed: seed(week + "#\(round)")) }

    /// Every tournament week from the first one to the one open for sign-ups (to delete an account).
    public static func weeks(untilMs: Int) -> [String] {
        guard let first = deadlineMs(week: "2026-11-09"), let last = deadlineMs(week: nextWeek(nowMs: untilMs)) else { return [] }
        return stride(from: first, through: last, by: 7 * dayMs).map { civil(floorDiv($0, dayMs)) }
    }
    /// FNV-1a, 64 bits: the same seed on both platforms.
    public static func seed(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        return hash
    }

    // Calendar arithmetic on days since 1970-01-01 (a Thursday), so no time zone is involved.
    static func weekday(_ day: Int) -> Int { ((day + 3) % 7 + 7) % 7 }
    static func floorDiv(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : -((-a + b - 1) / b) }
    static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = floorDiv(y, 400)
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
    static func civil(_ days: Int) -> String {
        let z = days + 719_468
        let era = floorDiv(z, 146_097)
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}

public struct TournamentPlayer: Codable, Sendable, Equatable {
    public var uid: String
    public var name: String
    public var atMs: Int
    public init(uid: String, name: String, atMs: Int) { self.uid = uid; self.name = name; self.atMs = atMs }
}

/// One player's 5 words in one round, timed by the server.
public struct TournamentRun: Codable, Sendable, Equatable {
    public var uid: String
    public var round: Int
    public var startedMs: Int
    public var finishedMs: Int?
    public var skips = 0
    public var errors = 0
    public init(uid: String, round: Int, startedMs: Int, finishedMs: Int? = nil, skips: Int = 0, errors: Int = 0) {
        self.uid = uid; self.round = round; self.startedMs = startedMs; self.finishedMs = finishedMs; self.skips = skips; self.errors = errors
    }
    public var scoreMs: Int? { finishedMs.map { $0 - startedMs + skips * ChallengeRules.skipPenaltyMs } }
}

public struct TournamentBracket: Sendable, Equatable {
    public enum Slot: Sendable, Equatable {
        case player(TournamentPlayer)
        /// Nobody: a bye, or a match where neither player played.
        case empty
        /// Not known yet: the match before is still being played.
        case pending
        public var player: TournamentPlayer? { if case .player(let p) = self { return p }; return nil }
    }
    public struct Match: Sendable, Equatable {
        public var a: Slot
        public var b: Slot
        /// A third player when the round has an odd number of players: the fastest of the three goes through.
        public var c: Slot?
        /// Decided: who goes through (nil when nobody does).
        public var decided = false
        public var winner: TournamentPlayer?
        /// For each slot (a, b, then c), the match of the round before it comes from (empty in round 1).
        public var from: [Int] = []
        public init(a: Slot, b: Slot, c: Slot? = nil, from: [Int] = []) { self.a = a; self.b = b; self.c = c; self.from = from }
        public var slots: [Slot] { c.map { [a, b, $0] } ?? [a, b] }
        public func has(_ uid: String) -> Bool { slots.contains { $0.player?.uid == uid } }
        public func opponent(of uid: String) -> Slot { a.player?.uid == uid ? b : a }
        /// The others of my match (one, or two in a match of 3).
        public func opponents(of uid: String) -> [Slot] {
            guard let index = slots.firstIndex(where: { $0.player?.uid == uid }) else { return slots }
            var others = slots; others.remove(at: index); return others
        }
        /// Where the slot at this position comes from, as a previous-round match index.
        public func source(_ position: Int) -> Int? { position < from.count ? from[position] : nil }
    }

    public let week: String
    /// The players in the draw: the first 64 signed up.
    public let players: [TournamentPlayer]
    public private(set) var rounds: [[Match]] = []

    /// The bracket as it stands at `nowMs` (the server's time) given the runs read so far.
    public init(week: String, signedUp: [TournamentPlayer], runs: [TournamentRun], nowMs: Int) {
        self.week = week
        var entrants = Array(signedUp.sorted { ($0.atMs, $0.uid) < ($1.atMs, $1.uid) }.prefix(TournamentRules.maxPlayers))
        var random = ModeRandom(seed: TournamentRules.seed(week))
        if entrants.count > 1 {
            for i in stride(from: entrants.count - 1, to: 0, by: -1) { entrants.swapAt(i, random.int(i + 1)) }
        }
        players = entrants
        let total = TournamentRules.rounds(players: entrants.count, week: week)
        guard total > 0 else { return }
        var byKey: [String: TournamentRun] = [:]
        for run in runs { byKey["\(run.round)_\(run.uid)"] = run }
        if TournamentRules.everyonePlays(week: week) {
            // Everyone plays every round: neighbours meet; with an odd number, the last match is played by 3.
            var slots: [Slot] = entrants.map { .player($0) }
            for round in 1...total {
                let end = TournamentRules.roundEndMs(week: week, round: round) ?? 0
                let count = slots.count / 2
                var matches: [Match] = (0..<count).map { i in
                    var match = Match(a: slots[2 * i], b: slots[2 * i + 1], from: round > 1 ? [2 * i, 2 * i + 1] : [])
                    if i == count - 1, slots.count % 2 == 1 {
                        match.c = slots[2 * i + 2]
                        if round > 1 { match.from.append(2 * i + 2) }
                    }
                    return match
                }
                matches = matches.map { Self.decide($0, round: round, end: end, now: nowMs, runs: byKey) }
                rounds.append(matches)
                slots = matches.map(Self.next)
            }
            return
        }
        let half = (1 << total) / 2
        var current: [Match] = (0..<half).map { k in
            Match(a: .player(entrants[k]), b: k + half < entrants.count ? .player(entrants[k + half]) : .empty)
        }
        for round in 1...total {
            let end = TournamentRules.roundEndMs(week: week, round: round) ?? 0
            current = current.map { Self.decide($0, round: round, end: end, now: nowMs, runs: byKey) }
            rounds.append(current)
            guard round < total else { break }
            current = stride(from: 0, to: current.count, by: 2).map { k in
                Match(a: Self.next(current[k]), b: Self.next(current[k + 1]), from: [k, k + 1])
            }
        }
    }

    private static func next(_ match: Match) -> Slot {
        guard match.decided else { return .pending }
        return match.winner.map { .player($0) } ?? .empty
    }

    private static func decide(_ match: Match, round: Int, end: Int, now: Int, runs: [String: TournamentRun]) -> Match {
        var m = match
        if m.slots.contains(.pending) { return m }
        let players = m.slots.compactMap(\.player)
        // Nobody, or one player alone: decided at once.
        guard players.count >= 2 else { m.decided = true; m.winner = players.first; return m }
        let scored = players.compactMap { p -> (TournamentPlayer, TournamentRun)? in
            guard let run = runs["\(round)_\(p.uid)"], let finished = run.finishedMs, finished <= end, run.scoreMs != nil else { return nil }
            return (p, run)
        }
        // Everyone finished: no need to wait for the end of the day.
        guard scored.count == players.count || now >= end else { return m }
        m.decided = true
        m.winner = scored.min { Self.better($0.1, $1.1) }?.0
        return m
    }
    /// Best time, then fewer errors, then the first one to finish.
    static func better(_ x: TournamentRun, _ y: TournamentRun) -> Bool {
        let sx = x.scoreMs ?? .max, sy = y.scoreMs ?? .max
        if sx != sy { return sx < sy }
        if x.errors != y.errors { return x.errors < y.errors }
        if x.finishedMs != y.finishedMs { return (x.finishedMs ?? .max) < (y.finishedMs ?? .max) }
        return x.uid < y.uid
    }

    /// The match of the next round that match `index` of `round` leads to, and the positions of the others in it.
    public func following(round: Int, index: Int) -> (match: Match, others: [Int])? {
        guard round < rounds.count, let match = rounds[round].first(where: { $0.from.contains(index) }) else { return nil }
        return (match, match.from.indices.filter { match.from[$0] != index })
    }

    /// The champion, once the final is decided.
    public var champion: TournamentPlayer? { rounds.last?.first.flatMap { $0.decided ? $0.winner : nil } }

    public enum Standing: Equatable, Sendable {
        /// Not in the draw (signed up too late, or not at all).
        case out
        /// My match of this round: to play, or waiting for the other one / the end of the day.
        case match(round: Int, Match)
        /// Waiting for the next round to open.
        case through(round: Int)
        case eliminated(round: Int)
        case champion
    }

    public func standing(of uid: String, nowMs: Int) -> Standing {
        guard players.contains(where: { $0.uid == uid }) else { return .out }
        for (index, matches) in rounds.enumerated() {
            let round = index + 1
            guard let match = matches.first(where: { $0.has(uid) }) else { return .through(round: round) }
            if !match.decided { return .match(round: round, match) }
            if match.winner?.uid != uid { return .eliminated(round: round) }
            if round == rounds.count { return .champion }
            // Through: shown on this round until the next one opens.
            if nowMs < (TournamentRules.roundEndMs(week: week, round: round) ?? 0) { return .match(round: round, match) }
        }
        return .out
    }
}

public enum TournamentFormat {
    /// A slot's name: the player, "personne", or where it comes from: "Gagnant de Léa / Sam", or
    /// "Gagnant du match 3" while that match is not known yet either.
    public static func slotName(_ bracket: TournamentBracket, round: Int, match: TournamentBracket.Match, position: Int) -> String {
        let slots = match.slots
        guard position < slots.count else { return "" }
        switch slots[position] {
        case .player(let p): return p.name
        case .empty: return "personne"
        case .pending:
            guard round > 1, round - 2 < bracket.rounds.count, let source = match.source(position),
                  source < bracket.rounds[round - 2].count else { return "à venir" }
            let before = bracket.rounds[round - 2][source]
            let names = before.slots.compactMap { $0.player?.name }
            return names.count == before.slots.count ? "Gagnant de " + names.joined(separator: " / ") : "Gagnant du match \(source + 1)"
        }
    }

    /// "Finale", "Demi-finales", "Quarts de finale", "8es de finale", or "Tour 1".
    public static func roundName(_ round: Int, of total: Int) -> String {
        switch total - round {
        case 0: return "Finale"
        case 1: return "Demi-finales"
        case 2: return "Quarts de finale"
        case 3: return "8es de finale"
        case 4: return "16es de finale"
        default: return "Tour \(round)"
        }
    }
}

/// The tournament's local notifications (no server): the start of a tournament I signed up for, each
/// round while I am still in (sure when I am through, a "come and see" otherwise), and an evening
/// reminder when my match of the day is not played yet. Worked out again each time the app reads it.
public enum TournamentReminders {
    public struct Alert: Equatable, Sendable {
        public let id: String
        public let atMs: Int
        public let title: String
        public let body: String
    }
    /// 19:00 UTC, 20 h in Paris in winter: 11 hours after a round opens.
    public static let eveningAfterMs = 11 * 3_600_000

    /// `day` writes a moment for people ("mardi 9 h").
    public static func plan(nextWeek: String, nextMine: Bool, bracket: TournamentBracket?, uid: String?, runs: [TournamentRun],
                            nowMs: Int, day: (Int) -> String) -> [Alert] {
        var alerts: [Alert] = []
        if nextMine, let start = TournamentRules.deadlineMs(week: nextWeek), start > nowMs {
            alerts.append(Alert(id: "start", atMs: start, title: "Le tournoi commence !",
                                body: "Votre premier match est ouvert : 24 h pour le jouer, quand vous voulez."))
        }
        guard let bracket, let uid, bracket.players.contains(where: { $0.uid == uid }) else { return alerts }
        let week = bracket.week, total = bracket.rounds.count
        var from: Int?, sure: Int?
        switch bracket.standing(of: uid, nowMs: nowMs) {
        case .match(let round, let match):
            if !match.decided {
                let played = runs.contains { $0.round == round && $0.uid == uid && $0.finishedMs != nil }
                if !played, let start = TournamentRules.roundStartMs(week: week, round: round), let end = TournamentRules.roundEndMs(week: week, round: round),
                   let at = [start + eveningAfterMs, end - 2 * 3_600_000].first(where: { $0 > nowMs && $0 > start }) {
                    alerts.append(Alert(id: "late", atMs: at, title: "Votre match du tournoi vous attend",
                                        body: "Il vous reste jusqu’à \(day(end)) pour le jouer. Ne laissez pas filer votre place !"))
                }
            } else {
                sure = round + 1
            }
            from = round + 1
        case .through(let round):
            sure = round + 1; from = round + 1
        default:
            break
        }
        if let from, from <= total {
            for round in from...total {
                guard let at = TournamentRules.roundStartMs(week: week, round: round), at > nowMs else { continue }
                let name = TournamentFormat.roundName(round, of: total)
                alerts.append(round == sure
                    ? Alert(id: "round\(round)", atMs: at, title: "Qualifié : " + name.lowercased(), body: "Votre match est ouvert : 24 h pour le jouer. Bonne chance !")
                    : Alert(id: "round\(round)", atMs: at, title: name + " du tournoi", body: "Le tour commence. Êtes-vous qualifié ? Venez voir votre match."))
            }
        }
        return alerts
    }
}

/// The bracket drawn like a football one: the first rounds on the left and on the right, the final in
/// the middle. The left half is what leads to the final's first player, the right half the others.
/// Positions in points: `column` from 0 (far left) to `columns - 1`, `y` the centre of the match.
public struct TournamentLayout: Sendable, Equatable {
    public enum Side: Sendable, Equatable { case left, center, right }
    public struct Node: Sendable, Equatable {
        public let round: Int
        public let index: Int
        public let side: Side
        public let column: Int
        public var y: Double
        public let height: Double
    }
    public private(set) var nodes: [Node] = []
    public private(set) var columns = 0
    public private(set) var height = 0.0

    /// `height(slots)`: a match card's height for 2 or 3 players; `gap`: between two first-round cards.
    public init(_ bracket: TournamentBracket, height: (Int) -> Double, gap: Double) {
        let rounds = bracket.rounds
        let total = rounds.count
        guard total > 0, let final = rounds[total - 1].first else { return }
        columns = 2 * total - 1
        if total == 1 {
            let h = height(final.slots.count)
            nodes = [Node(round: 1, index: 0, side: .center, column: 0, y: h / 2, height: h)]
            self.height = h
            return
        }
        var placed: [Node] = []
        func place(_ round: Int, _ index: Int, _ side: Side, _ cursor: inout Double) -> Double {
            let match = rounds[round - 1][index]
            let h = height(match.slots.count)
            let column = side == .left ? round - 1 : 2 * (total - 1) - (round - 1)
            var y: Double
            if round == 1 || match.from.isEmpty {
                y = cursor + h / 2
                cursor += h + gap
            } else {
                let ys = match.from.map { place(round - 1, $0, side, &cursor) }
                y = ((ys.first ?? 0) + (ys.last ?? 0)) / 2
            }
            placed.append(Node(round: round, index: index, side: side, column: column, y: y, height: h))
            return y
        }
        var left = 0.0, right = 0.0
        _ = final.from.prefix(1).map { place(total - 1, $0, .left, &left) }
        _ = final.from.dropFirst().map { place(total - 1, $0, .right, &right) }
        let leftHeight = max(0, left - gap), rightHeight = max(0, right - gap)
        let finalHeight = height(final.slots.count)
        let full = max(leftHeight, rightHeight, finalHeight)
        // The shorter half is centred against the taller one.
        nodes = placed.map { node in
            var moved = node
            moved.y += (full - (node.side == .left ? leftHeight : rightHeight)) / 2
            return moved
        }
        nodes.append(Node(round: total, index: 0, side: .center, column: total - 1, y: full / 2, height: finalHeight))
        self.height = full
    }

    public func node(round: Int, index: Int) -> Node? { nodes.first { $0.round == round && $0.index == index } }
}

/// Pictures only (screenshots): an invented tournament of 10, the second day under way. Round 1 is over
/// (I won mine), my match of the day is still to play, the others show who has played and who has not yet.
public enum TournamentDemo {
    public static let week = TournamentRules.everyonePlaysFrom
    public static func make(me: String, name: String) -> (players: [TournamentPlayer], runs: [TournamentRun], nowMs: Int) {
        let begin = TournamentRules.deadlineMs(week: week) ?? 0
        let names = ["Léa", "Sam", "Nadji", "Inès", "Hugo", "Maya", "Yanis", "Zoé", "Tom"]
        let players = [TournamentPlayer(uid: me, name: name, atMs: begin - 100_000)]
            + names.enumerated().map { TournamentPlayer(uid: "demo-t\($0.offset)", name: $0.element, atMs: begin - 90_000 + $0.offset) }
        let order = TournamentBracket(week: week, signedUp: players, runs: [], nowMs: begin).players
        var runs = order.enumerated().map { index, p in
            TournamentRun(uid: p.uid, round: 1, startedMs: begin + 3_600_000, finishedMs: begin + 3_600_000 + (p.uid == me ? 24_000 : 31_000 + index * 2_300),
                          skips: index % 4 == 3 ? 1 : 0, errors: index % 3)
        }
        let now = begin + TournamentRules.dayMs + 5 * 3_600_000
        let bracket = TournamentBracket(week: week, signedUp: players, runs: runs, nowMs: now)
        for match in bracket.rounds.count > 1 ? bracket.rounds[1] : [] where !match.has(me) {
            let present = match.slots.compactMap(\.player)
            if let first = present.first {
                runs.append(TournamentRun(uid: first.uid, round: 2, startedMs: now - 3_000_000, finishedMs: now - 2_960_000))
            }
            if present.count > 1 { runs.append(TournamentRun(uid: present[1].uid, round: 2, startedMs: now - 20_000)) }
        }
        return (players, runs, now)
    }
}
