import Foundation
import CNSNNCore

/// App Store screenshots (`--uitesting --screenshots`, see Tests/UI/CNSNNScreenshotTests.swift): an
/// invented, lively profile, leaderboard and friend challenges, all offline. Never active without
/// `--uitesting`, so real players never see it. Only public cards of the Classique deck appear on screen,
/// never a word of the secret Mot du jour.
enum ScreenshotDemo {
    static var isActive: Bool { RuntimeFlags.isTesting && ProcessInfo.processInfo.arguments.contains("--screenshots") }
    static let uid = "demo-camille"
    /// The word found today, shown on the home page.
    static var todayCard: Card { card("Croissant") }
    /// The Classique card being played.
    static var classicCard: Card { card("Papillon") }
    private static func card(_ word: String) -> Card { SeedCards.all.first { $0.wordFull == word } ?? SeedCards.all[0] }

    /// One invented player of the rankings.
    private struct Player: Sendable {
        let uid: String
        let name: String
        /// Average time per day this month.
        let averageMs: Int
        let bestMs: Int
        let streak: Int
        let bestStreak: Int
        let played: Int
        let wins: Int
        /// Today's Mot du jour: time, hint, wrong guesses.
        let todayMs: Int
        var hint = false
        var wrong = 0
    }
    private static let players: [Player] = [
        Player(uid: "demo-lea", name: "Léa", averageMs: 31_000, bestMs: 9_800, streak: 27, bestStreak: 41, played: 88, wins: 87, todayMs: 21_400),
        Player(uid: "demo-hugo", name: "Hugo", averageMs: 36_500, bestMs: 12_400, streak: 15, bestStreak: 22, played: 71, wins: 68, todayMs: 29_100, wrong: 1),
        Player(uid: "demo-ines", name: "Inès", averageMs: 41_200, bestMs: 15_100, streak: 9, bestStreak: 30, played: 93, wins: 89, todayMs: 44_700, wrong: 2),
        Player(uid: ScreenshotDemo.uid, name: "Camille", averageMs: 44_800, bestMs: 14_200, streak: 12, bestStreak: 19, played: 64, wins: 61, todayMs: 38_400),
        Player(uid: "demo-malo", name: "Malo", averageMs: 49_300, bestMs: 17_600, streak: 6, bestStreak: 14, played: 52, wins: 48, todayMs: 57_200),
        Player(uid: "demo-jade", name: "Jade", averageMs: 55_700, bestMs: 18_300, streak: 4, bestStreak: 11, played: 47, wins: 42, todayMs: 12_300, hint: true, wrong: 1),
        Player(uid: "demo-nora", name: "Nora", averageMs: 63_400, bestMs: 21_900, streak: 3, bestStreak: 9, played: 39, wins: 33, todayMs: 86_000, wrong: 3),
        Player(uid: "demo-sacha", name: "Sacha", averageMs: 70_900, bestMs: 24_500, streak: 2, bestStreak: 7, played: 31, wins: 25, todayMs: 123_500, wrong: 2),
    ]

    /// Fills the app once the pseudo is chosen: history, records, rankings and challenges.
    @MainActor static func fill(_ state: AppState) {
        let now = Date()
        let today = DailySchedule.key(now)
        var progress = state.progress

        // Classique: 164 cards over the last two weeks, 142 found, the last ones in a row.
        var attempts: [Attempt] = []
        let deck = SeedCards.all.filter { $0.id != todayCard.id && $0.id != classicCard.id }
        let classicGames = 164
        for index in 0..<classicGames {
            let card = deck[index % deck.count]
            let date = now.addingTimeInterval(-Double(classicGames - index) * 7_200 - 600)
            let correct = index >= 155 || index % 7 != 3
            attempts.append(Attempt(cardID: card.id, mode: .classic, correct: correct, timeMs: 9_000 + (index * 3_517) % 41_000,
                                    points: 0, date: date))
        }
        // Mot du jour: found today and the eleven days before (a 12-day streak).
        let dailyTimes = [38_400, 52_100, 27_800, 61_300, 44_900, 33_200, 71_600, 29_500, 48_700, 56_000, 35_900, 42_300]
        var day = now
        for (offset, timeMs) in dailyTimes.enumerated() {
            let cardID = offset == 0 ? todayCard.id : deck[(offset * 11) % deck.count].id
            attempts.append(Attempt(cardID: cardID, mode: .daily, correct: true, timeMs: timeMs, points: 0,
                                    date: offset == 0 ? now.addingTimeInterval(-1_800) : day, dailyKey: DailySchedule.key(day)))
            day = DailySchedule.previousDay(day)
        }
        progress.attempts = attempts.sorted { $0.date < $1.date }
        progress.recentCards = Array(attempts.filter { $0.mode == .classic }.map(\.cardID).suffix(20))

        // Personal records of the three modes.
        progress.recordMode(.sprint, best: [ModeStat.words: 23, ModeStat.combo: 7], add: [ModeStat.games: 41], device: "demo")
        progress.recordMode(.survival, best: [ModeStat.level: 6, ModeStat.words: 27], add: [ModeStat.games: 18], device: "demo")
        progress.recordMode(.duo, best: [ModeStat.duo: DuoRecord.value(solved: 5, ms: 74_000)],
                            add: [ModeStat.games: 12, ModeStat.perfect: 4, ModeStat.duosSolved: 51, ModeStat.duosPlayed: 60], device: "demo")
        state.progress = progress

        // Signed in (offline): the rankings below show who "vous" is.
        state.uid = uid
        state.isAnonymous = false
        state.email = nil

        // Every player found every word so far this week.
        let days = DailyScore.dayOfWeek(today)
        let weekIndex = DailyScore.weekIndex(today) ?? 0
        func week(_ p: Player) -> DailyScore.Week { DailyScore.Week(week: weekIndex, found: days, timeMs: p.averageMs * days, played: days) }
        let entries = players.map { p in
            LeaderboardEntry(uid: p.uid, username: p.uid == uid ? progress.username : p.name, played: p.played, wins: p.wins,
                             streak: p.streak, bestStreak: p.bestStreak, bestTimeMs: p.bestMs, lastWinDay: today,
                             week: weekIndex, weekFound: days, weekTimeMs: p.averageMs * days, weekPlayed: days)
        }
        state.official = entries.first { $0.uid == uid }
        state.rankings.players = entries.sorted { $0.weekTally.rank > $1.weekTally.rank }
        state.rankings.fastest = entries.sorted { ($0.bestTimeMs ?? 0) < ($1.bestTimeMs ?? 0) }
        state.rankings.myRank = (rank: 4, players: 1_287)
        state.rankings.today = players.map { p in
            DailyRank(uid: p.uid, username: p.uid == uid ? progress.username : p.name, timeMs: p.todayMs, usedHint: p.hint, wrongAnswers: p.wrong)
        }.sorted { $0.scoreMs < $1.scoreMs }
        state.rankings.friendCode = "K7M2QX"
        state.rankings.friends = FriendStanding.ordered(players.filter { ["demo-lea", "demo-hugo", "demo-jade", uid].contains($0.uid) }.map { p in
            FriendStanding(uid: p.uid, username: p.uid == uid ? progress.username : p.name, week: week(p), streak: p.streak,
                           today: Attempt(cardID: todayCard.id, mode: .daily, correct: true, timeMs: p.todayMs, points: 0, date: now, dailyKey: today),
                           todayWrong: p.wrong, todayHint: p.hint)
        })

        // Friend challenges: Léa's waits for you, three are over (two wins, one loss).
        let nowMs = Int(now.timeIntervalSince1970 * 1000)
        let hour = 3_600_000
        let me = progress.username
        func side(_ id: String, _ name: String, startedHoursAgo: Int?, ms: Int = 0) -> Challenge.Side {
            guard let startedHoursAgo else { return Challenge.Side(uid: id, name: name) }
            let start = nowMs - startedHoursAgo * hour
            return Challenge.Side(uid: id, name: name, startedMs: start, finishedMs: start + ms)
        }
        func challenge(_ id: String, hoursAgo: Int, seed: UInt64, from: Challenge.Side, to: Challenge.Side) -> Challenge {
            Challenge(id: id, cardIds: ChallengeRules.draw(seed: seed), createdMs: nowMs - hoursAgo * hour, from: from, to: to)
        }
        state.challenges = [
            challenge("demo-challenge-1", hoursAgo: 3, seed: 11, from: side("demo-lea", "Léa", startedHoursAgo: 3, ms: 96_000),
                      to: side(uid, me, startedHoursAgo: nil)),
            challenge("demo-challenge-2", hoursAgo: 30, seed: 12, from: side(uid, me, startedHoursAgo: 30, ms: 88_000),
                      to: side("demo-hugo", "Hugo", startedHoursAgo: 26, ms: 104_000)),
            challenge("demo-challenge-3", hoursAgo: 40, seed: 13, from: side("demo-jade", "Jade", startedHoursAgo: 40, ms: 131_000),
                      to: side(uid, me, startedHoursAgo: 38, ms: 92_000)),
            challenge("demo-challenge-4", hoursAgo: 46, seed: 14, from: side(uid, me, startedHoursAgo: 46, ms: 118_000),
                      to: side("demo-lea", "Léa", startedHoursAgo: 45, ms: 83_000)),
        ]
    }
}
