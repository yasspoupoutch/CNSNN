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
}
