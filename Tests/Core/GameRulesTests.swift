import XCTest
@testable import CNSNNCore
final class GameRulesTests: XCTestCase {
 func testDailyScoreIsTheTimePlusOneMinuteForTheHint() {
  XCTAssertEqual(DailyScore.scoreMs(timeMs:10000,usedHint:false,correct:true),10000)
  XCTAssertEqual(DailyScore.scoreMs(timeMs:10000,usedHint:true,correct:true),70000)
  XCTAssertEqual(DailyScore.scoreMs(timeMs:0,usedHint:false,correct:false),600000)
  XCTAssertEqual(DailyScore.scoreMs(timeMs:590000,usedHint:true,correct:true),600000)
  XCTAssertEqual(DailyScore.scoreMs(timeMs:3_600_000,usedHint:false,correct:true),600000)
 }
 func testDailyRankSortsByDayThenScore() {
  // Same numbers as the rules: days since 1970, lost words after every found one.
  XCTAssertEqual(DailyScore.dayIndex("1970-01-01"),0)
  XCTAssertEqual(DailyScore.dayIndex("2024-01-01"),19723)
  XCTAssertEqual(DailyScore.dayIndex("2026-10-16"),20742)
  XCTAssertEqual(DailyScore.rank(day:"2026-10-16",scoreMs:70000,correct:true),20742*1_000_000+70000)
  XCTAssertEqual(DailyScore.rank(day:"2026-10-16",scoreMs:600000,correct:false),20742*1_000_000+999_999)
  XCTAssertLessThan(DailyScore.rank(day:"2026-10-16",scoreMs:600000,correct:true)!,DailyScore.rank(day:"2026-10-16",scoreMs:600000,correct:false)!)
  XCTAssertEqual(DailyScore.monthIndex("2026-10-16"),2026*12+9)
 }
 func testTheMonthTotalStartsAgainEachMonth() {
  var month=DailyScore.Month(month:0,saved:0,played:0)
  month=DailyScore.tally(old:month,day:"2026-10-01",scoreMs:30000)
  month=DailyScore.tally(old:month,day:"2026-10-02",scoreMs:600000)
  XCTAssertEqual(month,DailyScore.Month(month:2026*12+9,saved:570000,played:2))
  // Two days: 30 s found and a lost day at 10 min, plus a third day not played yet at 10 min.
  XCTAssertEqual(DailyScore.monthTotal(saved:month.saved,days:3),1_230_000)
  XCTAssertEqual(month.rank,(2026*12+9)*100_000_000+570000)
  // A late result from September leaves October alone; November starts from zero.
  XCTAssertEqual(DailyScore.tally(old:month,day:"2026-09-30",scoreMs:1000),month)
  XCTAssertEqual(DailyScore.tally(old:month,day:"2026-11-01",scoreMs:600000),DailyScore.Month(month:2026*12+10,saved:0,played:1))
 }
 func testClassicLevelFollowsTheWordsFound() {
  XCTAssertEqual(ClassicLevel.level(words:0),1)
  XCTAssertEqual(ClassicLevel.level(words:19),1)
  XCTAssertEqual(ClassicLevel.level(words:20),2)
  XCTAssertEqual(ClassicLevel.into(words:45),5)
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
  XCTAssertEqual(copy.correctAnswers,2);XCTAssertEqual(copy.streak(at:today),2)
  XCTAssertEqual(copy.bestTimeMs,1000);XCTAssertEqual(copy.successRate,1)
 }
}
