import XCTest
@testable import CNSNNCore
final class NameFilterTests: XCTestCase {
    func testOffensivePseudosAreRefused() {
        for name in ["Connard", "gros c0nnard", "P.U.T.A.I.N", "Bâtard 93", "FDP", "pute", "Nazi", "S4lope"] {
            XCTAssertFalse(NameFilter.isAllowed(name), name)
        }
    }
    func testOrdinaryPseudosStay() {
        for name in ["Monique", "Computer", "Nazim", "Constance", "Pedro", "Yasin", "Poupoutch", "Violette", "Montenegro", "Alexandre"] {
            XCTAssertTrue(NameFilter.isAllowed(name), name)
        }
    }
    func testAutomaticPseudo() {
        for _ in 0..<200 {
            let name = NameFilter.automatic()
            XCTAssertTrue(NameFilter.isAutomatic(name), name)
            XCTAssertTrue(NameFilter.isAllowed(name), name)
            XCTAssertTrue((2...20).contains(name.count), name)
        }
        for name in ["Joueur", "Joueur123", "Joueur123456", "joueur4821", "Joueur48a1", "Camille", "Joueur 4821"] {
            XCTAssertFalse(NameFilter.isAutomatic(name), name)
        }
    }
    func testPseudoOfferAfterFirstWordOrGame() {
        var progress = Progress()
        progress.username = "Joueur4821"
        XCTAssertFalse(progress.pseudoOfferDue(offered: false), "Nothing played yet")
        progress.attempts.append(Attempt(cardID: "x", mode: .classic, correct: false, timeMs: 1000, points: 0, date: Date()))
        XCTAssertFalse(progress.pseudoOfferDue(offered: false), "A missed word is not enough")
        var sprint = progress
        sprint.recordMode(.sprint, best: [ModeStat.words: 0], add: [ModeStat.games: 1], device: "d")
        XCTAssertTrue(sprint.pseudoOfferDue(offered: false), "A first Sprint game, even with no word")
        progress.attempts.append(Attempt(cardID: "y", mode: .daily, correct: true, timeMs: 1000, points: 50, date: Date()))
        XCTAssertTrue(progress.pseudoOfferDue(offered: false))
        XCTAssertFalse(progress.pseudoOfferDue(offered: true), "Offered once only")
        progress.username = "Camille"
        XCTAssertFalse(progress.pseudoOfferDue(offered: false), "A chosen pseudo")
    }
}
