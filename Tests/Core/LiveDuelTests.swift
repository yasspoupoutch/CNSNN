import XCTest
@testable import CNSNNCore

final class LiveDuelTests: XCTestCase {
    private func duel(start: Int? = 10_000, from: LiveDuel.Side? = nil, to: LiveDuel.Side? = nil) -> LiveDuel {
        LiveDuel(id: "d", cardIds: [], createdMs: 0, startMs: start,
                 from: from ?? .init(uid: "alice", name: "Alice"), to: to ?? .init(uid: "bob", name: "Bob"))
    }

    func testWaitingCountdownPlaying() {
        var d = duel(start: nil, to: .init(uid: "", name: ""))
        XCTAssertTrue(d.isOpen)
        XCTAssertEqual(d.state(for: "alice", now: 1_000), .waiting)
        XCTAssertFalse(d.joinClosed(now: 14 * 60_000))
        XCTAssertTrue(d.joinClosed(now: 15 * 60_000))
        d.to = .init(uid: "bob", name: "Bob"); d.startMs = 10_000
        XCTAssertEqual(d.state(for: "bob", now: 6_000), .countdown)
        XCTAssertEqual(d.state(for: "bob", now: 10_000), .playing)
    }

    func testFirstToFinishWinsOnceTheOtherCanNoLongerCatchUp() {
        // Alice: 50 s with one pass = 70 s.
        let d = duel(from: .init(uid: "alice", name: "Alice", done: 5, skips: 1, finishedMs: 60_000))
        XCTAssertEqual(d.state(for: "alice", now: 60_000), .finished)
        XCTAssertNil(d.result(for: "bob", now: 70_000))
        XCTAssertEqual(d.leftToBeatMs(for: "alice", now: 70_000), 10_000)
        XCTAssertEqual(d.result(for: "alice", now: 80_001), .won)
        XCTAssertEqual(d.result(for: "bob", now: 80_001), .lost)
        // Bob passed a word too: he can no longer win after 50 s.
        var passed = d
        passed.to.skips = 1
        XCTAssertEqual(passed.result(for: "alice", now: 60_001), .won)
    }

    func testBothFinishedBestScoreThenDraw() {
        var d = duel(from: .init(uid: "alice", name: "Alice", done: 5, skips: 1, finishedMs: 60_000),
                     to: .init(uid: "bob", name: "Bob", done: 5, finishedMs: 75_000))
        XCTAssertEqual(d.result(for: "bob", now: 75_000), .won)
        d.to.finishedMs = 80_000
        XCTAssertEqual(d.result(for: "alice", now: 80_000), .draw)
    }

    func testQuitLosesAndTimeLimit() {
        var d = duel()
        d.to.quit = true
        XCTAssertEqual(d.result(for: "alice", now: 20_000), .won)
        XCTAssertEqual(d.result(for: "bob", now: 20_000), .lost)
        d.from.quit = true
        XCTAssertEqual(d.result(for: "bob", now: 20_000), .draw)
        let slow = duel()
        XCTAssertNil(slow.result(for: "alice", now: 10_000 + LiveDuelRules.maxMs - 1))
        XCTAssertEqual(slow.result(for: "alice", now: 10_000 + LiveDuelRules.maxMs), .draw)
    }

    func testServerClock() {
        var clock = ServerClock()
        clock.learn(serverMs: 10_500, sentMs: 1_000, receivedMs: 1_400)
        XCTAssertEqual(clock.offsetMs, 9_300)
        XCTAssertEqual(clock.now(localMs: 2_000), 11_300)
    }

    func testInviteTextCarriesTheLink() {
        XCTAssertTrue(LiveDuelInvite.shareText(code: "ABC234").contains("https://cnsnn-9ctosy.web.app/d/ABC234"))
    }
}
