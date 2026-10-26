import XCTest
@testable import CNSNNCore

final class ChallengeTests: XCTestCase {
    private let hour = 3_600_000

    func testDrawMatchesTheReference() {
        for item in ModeVectors.challenge {
            XCTAssertEqual(item.cards, ChallengeRules.draw(seed: item.seed, recent: item.recent), "graine \(item.seed)")
        }
    }

    func testTwoEasyTwoMediumOneHardDistinctPublicWords() {
        for seed: UInt64 in [1, 2, 3, 99, 12345] {
            let ids = ChallengeRules.draw(seed: seed)
            XCTAssertEqual(Set(ids).count, 5)
            let cards = try! XCTUnwrap(ChallengeRules.cards(ids))
            XCTAssertEqual(cards.map(\.difficulty), [.easy, .easy, .medium, .medium, .hard])
        }
        XCTAssertNil(ChallengeRules.cards(["inconnu", "a", "b", "c", "d"]))
    }

    func testGameCountsErrorsAndSkipsAndAddsTwentySecondsPerSkip() {
        var game = ChallengeGame(cards: ChallengeRules.cards(ChallengeRules.draw(seed: 7))!)
        XCTAssertEqual(game.answer("ZZZ"), .wrong)
        XCTAssertEqual(game.answer(game.card!.wordFull), .right)
        let passed = game.card!.wordFull
        game.skip()
        XCTAssertEqual(game.missed, [passed])
        while let card = game.card { game.answer(card.wordFull) }
        XCTAssertTrue(game.finished)
        XCTAssertEqual(game.answer("X"), .over)
        XCTAssertEqual(game.found, 4); XCTAssertEqual(game.skips, 1); XCTAssertEqual(game.errors, 1)
        XCTAssertEqual(game.scoreMs(elapsed: 60_000), 80_000)
    }

    private func challenge(from: Challenge.Side? = nil, to: Challenge.Side? = nil) -> Challenge {
        Challenge(id: "c", cardIds: [], createdMs: 0,
                  from: from ?? .init(uid: "alice", name: "Alice", startedMs: 0),
                  to: to ?? .init(uid: "bob", name: "Bob"))
    }

    func testBestTimeWinsThenFewerErrorsThenDraw() {
        let c = challenge(from: .init(uid: "alice", name: "Alice", startedMs: 0, finishedMs: 60_000, skips: 1, errors: 0),
                          to: .init(uid: "bob", name: "Bob", startedMs: 1_000, finishedMs: 71_000, skips: 0, errors: 5))
        // Alice 80 s with the skip, Bob 70 s.
        XCTAssertEqual(c.result(for: "bob", now: 2 * hour), .won)
        XCTAssertEqual(c.result(for: "alice", now: 2 * hour), .lost)
        var tie = c
        tie.to.finishedMs = 81_000
        XCTAssertEqual(tie.result(for: "alice", now: 0), .won)
        tie.to.errors = 0
        XCTAssertEqual(tie.result(for: "bob", now: 0), .draw)
    }

    func testStatesWhileOpen() {
        var c = challenge()
        XCTAssertEqual(c.state(for: "bob", now: hour), .yourTurn)
        XCTAssertEqual(c.state(for: "alice", now: hour), .playing)
        c.from.finishedMs = 90_000
        XCTAssertEqual(c.state(for: "alice", now: hour), .waiting)
        c.to.startedMs = 2 * hour
        XCTAssertEqual(c.state(for: "bob", now: 2 * hour), .playing)
    }

    func testDeadlines() {
        var c = challenge(from: .init(uid: "alice", name: "Alice", startedMs: 0, finishedMs: 90_000))
        XCTAssertNil(c.result(for: "alice", now: 47 * hour))
        // Bob never started: nobody wins.
        XCTAssertEqual(c.state(for: "alice", now: 48 * hour), .over(.expired))
        // Bob started but never finished: Alice wins after 50 h.
        c.to.startedMs = 10 * hour
        XCTAssertNil(c.result(for: "alice", now: 49 * hour))
        XCTAssertEqual(c.result(for: "alice", now: 50 * hour), .won)
        XCTAssertEqual(c.result(for: "bob", now: 50 * hour), .lost)
        // Neither finished.
        c.from.finishedMs = nil
        XCTAssertEqual(c.result(for: "alice", now: 50 * hour), .expired)
    }

    func testTallyPerFriend() {
        let won = challenge(from: .init(uid: "alice", name: "Alice", startedMs: 0, finishedMs: 50_000),
                            to: .init(uid: "bob", name: "Bob", startedMs: 0, finishedMs: 60_000))
        var lost = won; lost.from.finishedMs = 70_000
        var other = won; other.to.uid = "carol"
        var open = won; open.to.finishedMs = nil
        let all = [won, lost, other, open]
        XCTAssertEqual(ChallengeTally.of(all, me: "alice", friend: "bob", now: hour), ChallengeTally(wins: 1, losses: 1))
        XCTAssertEqual(ChallengeTally.of(all, me: "bob", friend: "alice", now: hour), ChallengeTally(wins: 1, losses: 1))
        XCTAssertEqual(ChallengeTally.of(all, me: "alice", now: hour), ChallengeTally(wins: 2, losses: 1))
        XCTAssertEqual(ChallengeTally(wins: 2, losses: 1).label, "2 victoires · 1 défaite")
        XCTAssertEqual(ChallengeTally(wins: 0, losses: 0, draws: 1).label, "0 victoire · 0 défaite · 1 égalité")
        XCTAssertNil(ChallengeTally().label)
    }

    func testFormats() {
        XCTAssertEqual(ChallengeFormat.time(118_400), "1:58")
        XCTAssertEqual(ChallengeFormat.time(724_000), "12:04")
        XCTAssertEqual(ChallengeFormat.left(31 * hour + 5), "31 h")
        XCTAssertEqual(ChallengeFormat.left(45 * 60_000), "45 min")
    }

    func testIdsStartWithTheTimeSoTheLatestComeAfterACursor() {
        XCTAssertEqual(ChallengeRules.newId(nowMs: 1234, random: "abc"), "0000000001234-abc")
        let now = 1_760_000_000_000
        XCTAssertEqual(ChallengeRules.newId(nowMs: now, random: "x"), "1760000000000-x")
        XCTAssertEqual(ChallengeRules.recentFromId(nowMs: now), String(now - 52 * hour))
        XCTAssertGreaterThan(ChallengeRules.newId(nowMs: now - 51 * hour, random: "zz"), ChallengeRules.recentFromId(nowMs: now))
        XCTAssertLessThan(ChallengeRules.newId(nowMs: now - 53 * hour, random: "zz"), ChallengeRules.recentFromId(nowMs: now))
        XCTAssertEqual(ChallengeRules.recentFromId(nowMs: 0), "0000000000000")
    }

    func testAlertsForANewChallengeAndForAResultOnlyOnce() {
        let sent = Challenge(id: "c", cardIds: [], createdMs: 0, from: .init(uid: "alice", name: "Alice", startedMs: 0, finishedMs: 60_000), to: .init(uid: "bob", name: "Bob"))
        // Bob is challenged; Alice (who sent it) gets nothing yet.
        let forBob = ChallengeAlerts.pending([sent], uid: "bob", now: hour, seen: [])
        XCTAssertEqual(forBob.map(\.key), ["c.new"])
        XCTAssertEqual(forBob.first?.title, "Alice vous a défié !")
        XCTAssertEqual(forBob.first?.body, "Mêmes 5 mots, le plus rapide gagne. Plus que 47 h pour jouer.")
        XCTAssertTrue(ChallengeAlerts.pending([sent], uid: "alice", now: hour, seen: []).isEmpty)
        XCTAssertTrue(ChallengeAlerts.pending([sent], uid: "bob", now: hour, seen: ["c.new"]).isEmpty)
        // Bob finished after Alice: Alice hears the result, Bob saw it on screen.
        var done = sent
        done.to = .init(uid: "bob", name: "Bob", startedMs: 2 * hour, finishedMs: 2 * hour + 90_000)
        let forAlice = ChallengeAlerts.pending([done], uid: "alice", now: 3 * hour, seen: [])
        XCTAssertEqual(forAlice.map(\.key), ["c.done"])
        XCTAssertEqual(forAlice.first?.title, "Victoire contre Bob !")
        XCTAssertEqual(forAlice.first?.body, "Votre chrono : 1:00 · Bob : 1:30")
        XCTAssertTrue(ChallengeAlerts.pending([done], uid: "bob", now: 3 * hour, seen: []).isEmpty)
        // Lost and draw titles; an expired challenge says nothing.
        var slow = done
        slow.to.finishedMs = 2 * hour + 30_000
        XCTAssertEqual(ChallengeAlerts.all([slow], uid: "alice", now: 3 * hour).map(\.title), ["Défaite contre Bob"])
        var tie = done
        tie.to.finishedMs = 2 * hour + 60_000
        XCTAssertEqual(ChallengeAlerts.all([tie], uid: "alice", now: 3 * hour).map(\.title), ["Égalité avec Bob"])
        XCTAssertTrue(ChallengeAlerts.all([sent], uid: "alice", now: 49 * hour).isEmpty)
        XCTAssertTrue(ChallengeAlerts.all([sent], uid: "bob", now: 49 * hour).isEmpty)
        XCTAssertTrue(ChallengeAlerts.all([sent], uid: "carol", now: hour).isEmpty)
    }

    /// The phone keeps the old challenges (frozen after 50 h) and reads only the recent ones.
    func testMergeKeepsFrozenChallengesAndTakesTheRecentOnes() {
        let now = 1_800_000_000_000
        func make(_ hoursAgo: Int, finished: Bool = false) -> Challenge {
            let created = now - hoursAgo * hour
            return Challenge(id: ChallengeRules.newId(nowMs: created, random: "r\(hoursAgo)"), cardIds: [], createdMs: created,
                             from: .init(uid: "alice", name: "Alice", startedMs: created, finishedMs: finished ? created + 60_000 : nil), to: .init(uid: "bob", name: "Bob"))
        }
        let old = make(100, finished: true), recentStale = make(3), recentFresh = make(3, finished: true), gone = make(10), new = make(1)
        let merged = ChallengeRules.merge(cached: [old, recentStale, gone], recent: [recentFresh, new], nowMs: now)
        // The recent list replaces what was cached for that period (a deleted one disappears).
        XCTAssertEqual(merged.map(\.id), [new.id, recentFresh.id, old.id])
        XCTAssertTrue(merged[1].from.finished)
    }
    /// Background checks: every 30 minutes, none at night, none just after the app read the challenges.
    func testBackgroundChecksArePaced() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 21))!
        XCTAssertEqual(ChallengeRules.nextCheck(after: evening, calendar: calendar), evening.addingTimeInterval(1800))
        let lateNight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 23, minute: 45))!
        XCTAssertEqual(ChallengeRules.nextCheck(after: lateNight, calendar: calendar), calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 7))!)
        let night = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 3))!
        XCTAssertFalse(ChallengeRules.shouldCheck(at: night, lastReadMs: nil, calendar: calendar))
        let ms = Int(evening.timeIntervalSince1970 * 1000)
        XCTAssertTrue(ChallengeRules.shouldCheck(at: evening, lastReadMs: nil, calendar: calendar))
        XCTAssertFalse(ChallengeRules.shouldCheck(at: evening, lastReadMs: ms - 5 * 60_000, calendar: calendar))
        XCTAssertTrue(ChallengeRules.shouldCheck(at: evening, lastReadMs: ms - 20 * 60_000, calendar: calendar))
    }

    func testInviteCodesFromTextsAndLinks() {
        XCTAssertEqual(ChallengeInvite.code(in: "abc234"), "ABC234")
        XCTAssertEqual(ChallengeInvite.code(in: " ABC 234 "), "ABC234")
        XCTAssertEqual(ChallengeInvite.code(in: "https://cnsnn-9ctosy.web.app/d/ABC234"), "ABC234")
        XCTAssertEqual(ChallengeInvite.code(in: "cnsnn://d/abc234?x=1"), "ABC234")
        XCTAssertEqual(ChallengeInvite.code(in: ChallengeInvite.shareText(code: "XYZ789")), "XYZ789")
        XCTAssertNil(ChallengeInvite.code(in: "ABC23"))
        XCTAssertNil(ChallengeInvite.code(in: "ABO234"))
        XCTAssertNil(ChallengeInvite.code(in: "Bonjour"))
        let code = ChallengeInvite.newCode()
        XCTAssertEqual(ChallengeInvite.code(in: code), code)
    }

    func testOpenChallengeWaitsForSomeoneThenPlaysAsUsual() {
        var c = challenge(to: .init(uid: "", name: ""))
        c.code = "ABC234"
        XCTAssertTrue(c.isOpen)
        XCTAssertEqual(c.opponentName("alice"), "Défi par lien")
        c.from.finishedMs = 90_000
        XCTAssertEqual(c.state(for: "alice", now: hour), .waiting)
        XCTAssertEqual(c.result(for: "alice", now: 49 * hour), .expired)
        c.to = .init(uid: "carol", name: "Carol")
        XCTAssertFalse(c.isOpen)
        XCTAssertEqual(c.opponentName("alice"), "Carol")
        XCTAssertEqual(c.state(for: "carol", now: hour), .yourTurn)
    }

    func testRenamingShowsTheCurrentPseudos() {
        let c = challenge().renaming(["bob": "Bobby", "zoe": "Zoé", "alice": ""])
        XCTAssertEqual(c.from.name, "Alice")
        XCTAssertEqual(c.to.name, "Bobby")
        XCTAssertEqual(c.opponentName("alice"), "Bobby")
    }
}
