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
  XCTAssertEqual(WordEngine.shownConsonants("Spider-Man"),"SPDR MN")
  XCTAssertEqual(WordEngine.shownConsonants("Rouge-gorge"),"RG GRG")
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

    func testTypedAnswerCaret() {
        var typed = TypedAnswer(text: "")
        typed.insert(" ")
        XCTAssertEqual(typed.text, "", "No leading space")
        "CHVAL".forEach { typed.insert(String($0)) }
        XCTAssertNil(typed.cursor)
        // A typo fixed in the middle: back two letters, add the missing E.
        typed.move(by: -2)
        XCTAssertEqual(typed.cursor, 3)
        typed.insert("E")
        XCTAssertEqual(typed.text, "CHEVAL")
        XCTAssertEqual(typed.position, 4)
        typed.deleteBackward()
        XCTAssertEqual(typed.text, "CHVAL")
        XCTAssertEqual(typed.position, 3)
        typed.move(by: 99)
        XCTAssertNil(typed.cursor, "Past the end goes back to the end")
        typed.place(-5)
        XCTAssertEqual(typed.position, 0)
        typed.deleteBackward()
        XCTAssertEqual(typed.text, "CHVAL", "Nothing to erase before the start")
        // No double spaces, on either side of the caret.
        typed = TypedAnswer(text: "LES ARISTOCHATS", cursor: 4)
        typed.insert(" ")
        XCTAssertEqual(typed.text, "LES ARISTOCHATS")
        typed.place(3)
        typed.insert(" ")
        XCTAssertEqual(typed.text, "LES ARISTOCHATS")
        // The text replaced behind the caret's back (a right answer clears it): the caret stays inside.
        typed.text = "AB"
        XCTAssertEqual(typed.position, 2)
        typed.insert("C")
        XCTAssertEqual(typed.text, "ABC")
        XCTAssertEqual(String(repeating: "A", count: 40).count, TypedAnswer.maxLength)
        var full = TypedAnswer(text: String(repeating: "A", count: 40))
        full.insert("B")
        XCTAssertEqual(full.text.count, 40)
    }
}
