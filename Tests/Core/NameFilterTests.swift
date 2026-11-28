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
}
