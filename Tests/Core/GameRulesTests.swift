import XCTest
@testable import CNSNNCore
final class GameRulesTests: XCTestCase {
 func testScore() {
  XCTAssertEqual(Scoring.points(difficulty:.easy,timeMs:10000,usedHint:false,correct:true),90)
  XCTAssertEqual(Scoring.points(difficulty:.easy,timeMs:10000,usedHint:true,correct:true),45)
  XCTAssertEqual(Scoring.points(difficulty:.hard,timeMs:0,usedHint:false,correct:false),0)
  XCTAssertEqual(Scoring.points(difficulty:.hard,timeMs:999999,usedHint:false,correct:true),150)
  XCTAssertEqual(Scoring.points(difficulty:.easy,timeMs:-1000,usedHint:false,correct:true),100)
 }
 private let paris=TimeZone(identifier:"Europe/Paris")!
 func testDailyDeterminismAndTimezone() throws {
  let date=try XCTUnwrap(ISO8601DateFormatter().date(from:"2026-10-05T22:30:00Z"))
  // The word follows the phone's time zone: these dates are checked on the Paris calendar.
  XCTAssertEqual(DailySchedule.key(date,in:paris),"2026-10-06")
  XCTAssertEqual(DailySchedule.key(date,in:TimeZone(identifier:"UTC")!),"2026-10-05")
  XCTAssertEqual(DailySchedule.card(for:date,cards:SeedCards.all),DailySchedule.card(for:date,cards:Array(SeedCards.all.reversed())))
  XCTAssertNil(DailySchedule.card(for:date,cards:[]))
 }
 func testDST() throws {
  let date=try XCTUnwrap(ISO8601DateFormatter().date(from:"2026-03-29T22:30:00Z"))
  XCTAssertEqual(DailySchedule.key(date,in:paris),"2026-03-30")
  XCTAssertEqual(DailySchedule.key(DailySchedule.previousDay(date,in:paris),in:paris),"2026-03-29")
 }
 func testNoImmediateRepeat() {
  let cards=Array(SeedCards.all.prefix(3))
  XCTAssertEqual(CardPicker.candidates(cards:cards,category:nil,difficulty:nil,recent:cards.map(\.id)).first?.id,cards[0].id)
  XCTAssertEqual(CardPicker.candidates(cards:cards,category:nil,difficulty:nil,recent:[cards[0].id]).count,2)
  XCTAssertTrue(CardPicker.candidates(cards:[],category:nil,difficulty:nil,recent:[]).isEmpty)
 }
 func testPersistenceAndStreak() throws {
  let today=try XCTUnwrap(ISO8601DateFormatter().date(from:"2026-10-06T12:00:00Z"))
  var p=Progress();p.username="Alice"
  for key in ["2026-10-05","2026-10-06"] {p.attempts.append(Attempt(cardID:"card",mode:.daily,correct:true,timeMs:1000,points:100,date:today,dailyKey:key))}
  let copy=try JSONDecoder().decode(Progress.self,from:JSONEncoder().encode(p))
  XCTAssertEqual(copy.score,200);XCTAssertEqual(copy.streak(at:today),2)
  XCTAssertEqual(copy.bestTimeMs,1000);XCTAssertEqual(copy.successRate,1)
 }
}
