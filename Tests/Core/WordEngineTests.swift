import XCTest
@testable import CNSNNCore
final class WordEngineTests: XCTestCase {
 func testConsonants() {
  XCTAssertEqual(WordEngine.consonants("CHOCOLAT"),"CHCLT")
  XCTAssertEqual(WordEngine.consonants("Éléphant"),"LPHNT")
  XCTAssertEqual(WordEngine.consonants("L’été"),"LT")
  XCTAssertEqual(WordEngine.consonants("œuf"),"F")
  XCTAssertEqual(WordEngine.consonants("Penalty"),"PNLT")
 }
 func testTheBoardSeparatesWords() {
  XCTAssertEqual(WordEngine.shownConsonants("Le Roi Lion"),"L R LN")
  XCTAssertEqual(WordEngine.shownConsonants("Où est Charlie ?"),"– ST CHRL")
  XCTAssertEqual(WordEngine.shownConsonants("Mission : Impossible"),"MSSN MPSSBL")
  XCTAssertEqual(WordEngine.shownConsonants("L’Âge de glace"),"LG D GLC")
  XCTAssertEqual(WordEngine.shownConsonants("Spider-Man"),"SPDRMN")
  XCTAssertEqual(WordEngine.shownConsonants("Papillon"),"PPLLN")
  XCTAssertEqual(Card(id: "x", wordFull: "Le Roi Lion", hint: "", category: .cinema, difficulty: .easy).wordNoVowels,"L R LN")
  XCTAssertEqual(WordEngine.spoken("L R LN"),"L ; R ; L, N")
 }
 func testFrenchNormalization() {
  XCTAssertEqual(WordEngine.normalize("  L’ŒUVRE — d'Été  "),"LOEUVREDETE")
  XCTAssertTrue(WordEngine.matches(" ballon d'or ",word:"Ballon d’or"))
  XCTAssertTrue(WordEngine.matches("elephant",word:"Éléphant"))
  XCTAssertFalse(WordEngine.matches("   ",word:""))
  XCTAssertFalse(WordEngine.matches("chocolats",word:"Chocolat"))
  XCTAssertFalse(WordEngine.validWord("AEIOUY"))
 }
 func testCatalogueInvariants() {
  XCTAssertEqual(Set(SeedCards.all.map(\.id)).count,SeedCards.all.count)
  XCTAssertTrue(SeedCards.all.allSatisfy { WordEngine.validWord($0.wordFull) && !$0.hint.isEmpty })
  XCTAssertEqual(Set(SeedCards.all.map(\.category)),Set(Category.allCases))
 }
}
