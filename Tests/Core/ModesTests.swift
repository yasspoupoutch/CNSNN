import XCTest
@testable import CNSNNCore

/// The scenarios of Scripts/generate_content.py, replayed step by step: Android replays the same ones.
final class ModeVectorsTests: XCTestCase {
    private func split(_ action: String) -> (String, Int) {
        let parts = action.split(separator: "@")
        return (String(parts[0]), Int(parts[1]) ?? 0)
    }

    func testRandomNumbersMatchTheReference() {
        for item in ModeVectors.random {
            var random = ModeRandom(seed: item.seed)
            XCTAssertEqual(item.values, item.values.map { _ in random.next() })
            var again = ModeRandom(seed: item.seed)
            XCTAssertEqual(item.mod97, again.int(97))
        }
    }

    func testSprintGamesMatchTheReference() {
        for item in ModeVectors.sprint {
            var game = SprintGame(seed: item.seed)
            XCTAssertEqual(item.first, game.card?.id)
            for step in item.steps {
                let (kind, at) = split(step.action)
                switch kind {
                case "ok": game.answer(game.card!.wordFull, elapsed: at)
                case "ko": game.answer("ZZZ", elapsed: at)
                default: game.skip(elapsed: at)
                }
                let label = "graine \(item.seed), \(step.action)"
                XCTAssertEqual(step.card, game.card?.id ?? "", label)
                XCTAssertEqual(step.streak, game.streak, label)
                XCTAssertEqual(step.found, game.found, label)
                XCTAssertEqual(step.wrong, game.wrong, label)
                XCTAssertEqual(step.skips, game.skips, label)
                XCTAssertEqual(step.remainingMs, game.remainingMs(elapsed: at), label)
                XCTAssertEqual(step.finished, game.finished, label)
            }
            XCTAssertEqual(item.bestCombo, game.bestCombo)
        }
    }

    func testSurvivalGamesMatchTheReference() {
        let names: [Difficulty: String] = [.easy: "easy", .medium: "medium", .hard: "hard"]
        for item in ModeVectors.survival {
            var game = SurvivalGame(seed: item.seed)
            for step in item.steps {
                switch step.action {
                case "ok": game.answer(game.card!.wordFull)
                case "ko": game.answer("ZZZ")
                default: game.skip()
                }
                let label = "graine \(item.seed), \(step.action)"
                XCTAssertEqual(step.card, game.card?.id ?? "", label)
                XCTAssertEqual(step.difficulty, game.card.flatMap { names[$0.difficulty] } ?? "", label)
                XCTAssertEqual(step.lives, game.lives, label)
                XCTAssertEqual(step.found, game.found, label)
                XCTAssertEqual(step.level, game.level, label)
                XCTAssertEqual(step.gained, game.livesGained, label)
                XCTAssertEqual(step.finished, game.finished, label)
            }
        }
    }

    func testDuoGamesMatchTheReference() {
        for item in ModeVectors.duo {
            var game = DuoGame(seed: item.seed)
            XCTAssertEqual(item.duos, game.duos.map(\.id))
            for step in item.steps {
                let (kind, at) = split(step.action)
                let duo = game.duos[min(game.round, game.duos.count - 1)]
                switch kind {
                case "a": game.answer(duo.first.word, elapsed: at)
                case "b": game.answer(duo.second.word, elapsed: at)
                case "ko": game.answer("ZZZ", elapsed: at)
                case "skip": game.skip(elapsed: at)
                default: game.next(elapsed: at)
                }
                let label = "graine \(item.seed), \(step.action)"
                XCTAssertEqual(step.round, game.round, label)
                XCTAssertEqual(step.found, game.wordsFound, label)
                XCTAssertEqual(step.solved, game.solved, label)
                XCTAssertEqual(step.errors, game.errors, label)
                XCTAssertEqual(step.playMs, game.playMs(elapsed: at), label)
                XCTAssertEqual(step.record, game.records(elapsed: at).best[ModeStat.duo], label)
                XCTAssertEqual(step.finished, game.finished, label)
            }
        }
    }
}

final class SprintTests: XCTestCase {
    @discardableResult private func right(_ game: inout SprintGame, _ at: Int) -> SprintGame.Outcome {
        game.answer(game.card!.wordFull, elapsed: at)
    }

    func testComboGrowsToFiveThenAWrongAnswerResetsIt() {
        var game = SprintGame(seed: 11)
        var combos: [Int] = []
        for second in 1...7 {
            if case .right(let combo) = right(&game, second * 1000) { combos.append(combo) }
        }
        XCTAssertEqual(combos, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(game.bestCombo, 7)
        XCTAssertEqual(game.answer("PASLEMOT", elapsed: 8000), .wrong)
        XCTAssertEqual(game.streak, 0)
    }

    func testTheResultIsTheWordsFound() {
        var game = SprintGame(seed: 3)
        for index in 0..<12 { right(&game, index * 500) }
        game.answer("PASLEMOT", elapsed: 7000)
        XCTAssertEqual(game.found, 12)
        XCTAssertEqual(game.records.best, [ModeStat.words: 12, ModeStat.combo: 12])
    }

    /// Same numbers as Firebase/tests/sprint.test.mjs: more words first, then the earlier game.
    func testSprintRankingSortsWordsThenTheEarlierGame() {
        XCTAssertEqual(SprintRecords.rank(best: 17, startedAtMs: 1000), 179_999_999_998_999)
        XCTAssertGreaterThan(SprintRecords.rank(best: 18, startedAtMs: 5000), SprintRecords.rank(best: 17, startedAtMs: 1000))
        XCTAssertGreaterThan(SprintRecords.rank(best: 17, startedAtMs: 1000), SprintRecords.rank(best: 17, startedAtMs: 5000))
        XCTAssertGreaterThan(SprintRecords.rank(best: 60, startedAtMs: 1_900_000_000_000), 0)
    }

    func testPassingCostsFiveSecondsAndTheCombo() {
        var game = SprintGame(seed: 5)
        right(&game, 1000); right(&game, 2000)
        let before = game.card?.id
        game.skip(elapsed: 3000)
        XCTAssertNotEqual(before, game.card?.id)
        XCTAssertEqual(game.streak, 0)
        XCTAssertEqual(game.remainingMs(elapsed: 3000), 90_000 - 3000 - 5000)
    }

    func testTheGameEndsAtZeroAndRefusesLateAnswers() {
        var game = SprintGame(seed: 8)
        XCTAssertFalse(game.tick(elapsed: 89_999))
        XCTAssertTrue(game.tick(elapsed: 90_000))
        XCTAssertEqual(game.answer(game.card!.wordFull, elapsed: 90_500), .over)
        XCTAssertEqual(game.found, 0)
    }

    func testTimeSpentInTheBackgroundStillCounts() {
        var game = SprintGame(seed: 9)
        right(&game, 10_000)
        XCTAssertEqual(game.answer(game.card!.wordFull, elapsed: 95_000), .over)
        XCTAssertTrue(game.finished)
        XCTAssertEqual(game.found, 1)
    }

    func testAGameNeverShowsTheSameWordTwice() {
        var game = SprintGame(seed: 21)
        for _ in 0..<150 { right(&game, 0) }
        XCTAssertEqual(game.used.count, Set(game.used).count)
    }

    func testPassedWordsAreKeptForTheEnd() throws {
        var game = SprintGame(seed: 41)
        let first = game.card!.wordFull
        game.skip(elapsed: 1000); right(&game, 2000)
        let second = game.card!.wordFull
        game.skip(elapsed: 3000)
        XCTAssertEqual(game.missed, [first, second])
        // A game saved by an older version has no list.
        let old = try JSONDecoder().decode(SprintGame.self, from: JSONEncoder().encode(SprintGame(seed: 41)))
        XCTAssertNil(old.missed)
    }

    func testASavedGameResumesIdentically() throws {
        var game = SprintGame(seed: 31)
        right(&game, 1000); game.answer("NON", elapsed: 2000)
        var copy = try JSONDecoder().decode(SprintGame.self, from: JSONEncoder().encode(game))
        XCTAssertEqual(copy.card, game.card)
        XCTAssertEqual(copy.found, game.found)
        right(&game, 3000); right(&copy, 3000)
        XCTAssertEqual(copy.card, game.card)
    }
}

final class SurvivalTests: XCTestCase {
    @discardableResult private func right(_ game: inout SurvivalGame) -> SurvivalGame.Outcome { game.answer(game.card!.wordFull) }

    func testThreeMistakesEndTheGame() {
        var game = SurvivalGame(seed: 1)
        XCTAssertEqual(game.answer("NON"), .wrong(livesLeft: 2))
        let passed = game.card!.wordFull
        game.skip()
        XCTAssertEqual(game.missed, [passed])
        XCTAssertEqual(game.lives, 1)
        XCTAssertEqual(game.answer("NON"), .wrong(livesLeft: 0))
        XCTAssertTrue(game.finished)
        XCTAssertEqual(game.mistakes, 3)
    }

    func testEveryTenthWordGivesALifeBackButNeverAFourth() {
        var game = SurvivalGame(seed: 2)
        for _ in 0..<10 { right(&game) }
        XCTAssertEqual(game.lives, 3)
        XCTAssertEqual(game.livesGained, 0)
        game.answer("NON")
        for _ in 0..<9 { right(&game) }
        XCTAssertEqual(game.lives, 2)
        XCTAssertEqual(right(&game), .right(lifeGained: true))
        XCTAssertEqual(game.lives, 3)
    }

    func testLevelsRiseEveryFiveWordsAndHardWordsComeLater() {
        var game = SurvivalGame(seed: 6)
        var seen: [(Int, Difficulty)] = []
        for _ in 0..<60 { seen.append((game.level, game.card!.difficulty)); right(&game) }
        XCTAssertEqual(game.level, 13)
        XCTAssertTrue(seen.filter { $0.0 == 1 }.allSatisfy { $0.1 == .easy })
        XCTAssertFalse(seen.filter { $0.0 <= 2 }.contains { $0.1 == .hard })
        let late = seen.filter { $0.0 >= 7 }
        XCTAssertGreaterThan(late.filter { $0.1 == .hard }.count, late.count / 2)
    }

    func testTheDifficultyTableAddsUpAndHardensSteadily() {
        for row in SurvivalGame.levels { XCTAssertEqual(row.reduce(0, +), 100) }
        let hard = SurvivalGame.levels.map { $0[2] }
        XCTAssertEqual(hard, hard.sorted())
    }
}

final class DuoTests: XCTestCase {
    func testEveryDuoIsValid() {
        var words = Set<String>(), sets = Set<String>()
        XCTAssertGreaterThanOrEqual(DuoBank.all.count, 30)
        for duo in DuoBank.all {
            let a = WordEngine.normalize(duo.first.word), b = WordEngine.normalize(duo.second.word)
            XCTAssertNotEqual(a, b, duo.id)
            XCTAssertEqual(WordEngine.consonants(duo.first.word), WordEngine.consonants(duo.second.word), duo.id)
            XCTAssertTrue(WordEngine.validWord(duo.first.word) && WordEngine.validWord(duo.second.word), duo.id)
            XCTAssertNotEqual(duo.first.hint, duo.second.hint, duo.id)
            for word in duo.words { XCTAssertFalse(WordEngine.normalize(word.hint).contains(WordEngine.normalize(word.word)), duo.id) }
            XCTAssertTrue(words.insert(a).inserted && words.insert(b).inserted, "doublon \(duo.id)")
            XCTAssertTrue(sets.insert(duo.consonants).inserted, "consonnes déjà jouées \(duo.id)")
        }
    }

    func testEachAnswerFillsItsOwnClue() {
        var game = DuoGame(seed: 12)
        let duo = game.duo!
        XCTAssertEqual(game.answer(duo.second.word.lowercased(), elapsed: 1000), .second)
        XCTAssertEqual(game.answer(duo.second.word, elapsed: 2000), .already)
        XCTAssertEqual(game.errors, 0)
        XCTAssertEqual(game.answer("XYZ", elapsed: 2500), .wrong)
        XCTAssertEqual(game.answer(duo.first.word, elapsed: 3000), .first)
        XCTAssertTrue(game.roundComplete)
    }

    func testAPerfectGameRecordsEveryPairAndItsTime() {
        var game = DuoGame(seed: 14)
        for index in 0..<DuoGame.rounds {
            let duo = game.duo!
            game.answer(duo.first.word, elapsed: index * 10_000 + 1000)
            game.answer(duo.second.word, elapsed: index * 10_000 + 2000)
            game.next(elapsed: index * 10_000 + 2000)
        }
        XCTAssertTrue(game.finished)
        XCTAssertTrue(game.perfect)
        XCTAssertEqual(game.playMs(elapsed: 99_000), 42_000)
        let record = game.records(elapsed: 99_000).best[ModeStat.duo]!
        XCTAssertEqual(DuoRecord.solved(record), 5)
        XCTAssertEqual(DuoRecord.seconds(record), 42)
        // More pairs always beat a faster game with fewer pairs.
        XCTAssertGreaterThan(DuoRecord.value(solved: 5, ms: 3_000_000), DuoRecord.value(solved: 4, ms: 1000))
        XCTAssertGreaterThan(DuoRecord.value(solved: 5, ms: 40_000), DuoRecord.value(solved: 5, ms: 42_000))
        XCTAssertEqual(game.records(elapsed: 99_000).add[ModeStat.perfect], 1)
    }

    func testAbandonCountsEveryRound() {
        var game = DuoGame(seed: 15)
        for _ in 0..<20 { game.answer("FAUX", elapsed: 1000) }
        XCTAssertEqual(DuoRecord.solved(game.records(elapsed: 2000).best[ModeStat.duo]!), 0)
        game.abandon(elapsed: 3000)
        XCTAssertTrue(game.finished)
        XCTAssertEqual(game.records(elapsed: 3000).add[ModeStat.duosPlayed], 5)
    }
}

final class CatalogueTests: XCTestCase {
    func testTheCatalogueHasHundredsOfCheckedCards() {
        let all = ModeCatalogue.cards
        XCTAssertGreaterThanOrEqual(all.count, 300)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        XCTAssertEqual(Set(all.map { WordEngine.normalize($0.wordFull) }).count, all.count)
        let daily = Set(DailyPool.all.map { WordEngine.normalize($0.wordFull) })
        for card in all {
            XCTAssertTrue(WordEngine.validWord(card.wordFull), card.id)
            XCTAssertFalse(WordEngine.normalize(card.hint).contains(WordEngine.normalize(card.wordFull)), card.id)
            XCTAssertFalse(daily.contains(WordEngine.normalize(card.wordFull)), card.id)
        }
        for level in Difficulty.allCases { XCTAssertGreaterThanOrEqual(all.filter { $0.difficulty == level }.count, 60) }
    }
}

final class ModeRecordsTests: XCTestCase {
    func testRecordsOnlyGrowAndReportWhatWasBeaten() {
        var progress = Progress()
        let first = progress.recordMode(.sprint, best: ["score": 120, "words": 6, "combo": 4], add: ["games": 1], device: "A")
        XCTAssertEqual(first, ["score", "words", "combo"])
        let second = progress.recordMode(.sprint, best: ["score": 90, "words": 8, "combo": 2], add: ["games": 1], device: "A")
        XCTAssertEqual(second, ["words"])
        XCTAssertEqual(progress.records(.sprint).best("score"), 120)
        XCTAssertEqual(progress.records(.sprint).total("games"), 2)
    }

    func testTwoPhonesPlayingOfflineKeepEveryGame() {
        var cloud = Progress(); cloud.username = "Lou"
        cloud.recordMode(.survival, best: ["words": 12, "level": 3], add: ["games": 1], device: "iphone")
        var iphone = cloud, android = cloud
        iphone.recordMode(.survival, best: ["words": 20, "level": 5], add: ["games": 1], device: "iphone")
        android.recordMode(.survival, best: ["words": 15, "level": 4], add: ["games": 1], device: "android")
        android.recordMode(.survival, best: ["words": 2, "level": 1], add: ["games": 1], device: "android")
        for merged in [iphone.merged(with: android), android.merged(with: iphone), iphone.merged(with: android).merged(with: android).merged(with: iphone)] {
            XCTAssertEqual(merged.records(.survival).best("words"), 20)
            XCTAssertEqual(merged.records(.survival).total("games"), 4)
        }
    }

    func testRecordsReadTheAndroidFormat() throws {
        let json = #"{"username":"Lou","attempts":[],"recentCards":[],"submissions":[],"dailyStarted":{},"dailyStartedAt":{},"modes":{"duo":{"best":{"score":900},"counts":{"games":{"d1":1},"duosSolved":{"d1":3}}}}}"#
        let progress = try JSONDecoder().decode(Progress.self, from: Data(json.utf8))
        XCTAssertEqual(progress.records(.duo).best("score"), 900)
        XCTAssertEqual(progress.records(.duo).total("duosSolved"), 3)
        let old = try JSONDecoder().decode(Progress.self, from: Data(#"{"username":"Lou","attempts":[],"recentCards":[],"submissions":[],"dailyStarted":{},"dailyStartedAt":{}}"#.utf8))
        XCTAssertNil(old.modes)
        XCTAssertEqual(old.merged(with: progress).records(.duo).best("score"), 900)
    }

    func testModeGamesNeverTouchTheClassicLevel() {
        var progress = Progress()
        progress.recordMode(.sprint, best: ["words": 50], add: ["games": 1], device: "A")
        XCTAssertEqual(progress.level, 1)
        XCTAssertTrue(progress.attempts.isEmpty)
    }
}
