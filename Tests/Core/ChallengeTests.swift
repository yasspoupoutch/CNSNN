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
        game.skip()
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
}
