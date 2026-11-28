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
 func testVowelsForTheFirstHint() {
  XCTAssertEqual(WordEngine.vowels("Amour"),"AOU")
  XCTAssertEqual(WordEngine.vowels("Éléphant"),"AE")
  XCTAssertEqual(WordEngine.vowels("œuf"),"EOU")
  XCTAssertEqual(WordEngine.vowels("Penalty"),"AEY")
  XCTAssertEqual(WordEngine.vowels("Rythme"),"EY")
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
  XCTAssertTrue(WordEngine.matches("SUPER MARIO",word:"Super Mario"))
  XCTAssertTrue(WordEngine.matches("calamar",word:"Calmar"))
  XCTAssertTrue(WordEngine.matches("calmar",word:"Calmar"))
  XCTAssertFalse(WordEngine.matches("calamar",word:"Calamar géant"))
  for (word, others) in WordEngine.variants {
   for other in others { XCTAssertEqual(WordEngine.consonants(other), WordEngine.consonants(word), other) }
  }
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
        // A typo fixed in the middle: back three letters, add the missing E.
        typed.move(by: -3)
        XCTAssertEqual(typed.cursor, 2)
        typed.insert("E")
        XCTAssertEqual(typed.text, "CHEVAL")
        XCTAssertEqual(typed.position, 3)
        typed.deleteBackward()
        XCTAssertEqual(typed.text, "CHVAL")
        XCTAssertEqual(typed.position, 2)
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

    /// Same vectors as Firebase/tests/daily.test.mjs placedVowels.
    func testPlacedVowelsOneByOneInOrder() {
        XCTAssertEqual(WordEngine.placedVowels("Œuvre").letters, 4)
        XCTAssertEqual(WordEngine.placedVowels("Œuvre").steps, ["OVR", "OEVR", "OEUVR"])
        XCTAssertEqual(WordEngine.placedVowels("Éléphant").steps, ["ELPHNT", "ELEPHNT"])
        XCTAssertEqual(WordEngine.placedVowels("Bus").letters, 1)
        XCTAssertEqual(WordEngine.placedVowels("Bus").steps, [])
    }
    func testPlacedVowelsCostThirtySecondsEachAndRevealedRanksAfterFound() {
        XCTAssertEqual(DailyScore.scoreMs(timeMs: 100_000, usedHint: true, usedVowels: true, letters: 2, correct: true), 220_000)
        XCTAssertEqual(DailyScore.scoreMs(timeMs: 590_000, usedHint: true, usedVowels: true, letters: 3, correct: true), 600_000)
        let found = DailyScore.rank(day: "2026-11-15", scoreMs: 600_000, correct: true)!
        let revealed = DailyScore.revealedRank(day: "2026-11-15", timeMs: 5_000)!
        let lost = DailyScore.rank(day: "2026-11-15", scoreMs: 600_000, correct: false)!
        XCTAssertTrue(found < revealed && revealed < lost)
    }
}
