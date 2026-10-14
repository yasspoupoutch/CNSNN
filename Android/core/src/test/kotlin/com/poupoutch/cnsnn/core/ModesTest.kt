package com.poupoutch.cnsnn.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The scenarios of Scripts/generate_content.py, replayed step by step: the iPhone replays the same ones. */
class ModeVectorsTest {
    @Test fun randomNumbersMatchTheReference() {
        for (case in ModeVectors.random) {
            val random = ModeRandom(case.seed)
            assertEquals(case.values, List(case.values.size) { random.next() })
            assertEquals(case.mod97, ModeRandom(case.seed).int(97))
        }
    }

    @Test fun sprintGamesMatchTheReference() {
        for (case in ModeVectors.sprint) {
            val game = SprintGame(case.seed)
            assertEquals(case.first, game.card?.id)
            for (step in case.steps) {
                val (kind, at) = step.action.split("@").let { it[0] to it[1].toInt() }
                when (kind) {
                    "ok" -> game.answer(game.card!!.wordFull, at)
                    "ko" -> game.answer("ZZZ", at)
                    else -> game.skip(at)
                }
                val label = "graine ${case.seed}, ${step.action}"
                assertEquals(label, step.card, game.card?.id ?: "")
                assertEquals(label, step.score, game.score)
                assertEquals(label, step.streak, game.streak)
                assertEquals(label, step.found, game.found)
                assertEquals(label, step.wrong, game.wrong)
                assertEquals(label, step.skips, game.skips)
                assertEquals(label, step.remainingMs, game.remainingMs(at))
                assertEquals(label, step.finished, game.finished)
            }
            assertEquals(case.bestCombo, game.bestCombo)
        }
    }

    @Test fun survivalGamesMatchTheReference() {
        for (case in ModeVectors.survival) {
            val game = SurvivalGame(case.seed)
            for (step in case.steps) {
                when (step.action) {
                    "ok" -> game.answer(game.card!!.wordFull)
                    "ko" -> game.answer("ZZZ")
                    else -> game.skip()
                }
                val label = "graine ${case.seed}, ${step.action}"
                assertEquals(label, step.card, game.card?.id ?: "")
                assertEquals(label, step.difficulty, game.card?.difficulty?.name?.lowercase() ?: "")
                assertEquals(label, step.lives, game.lives)
                assertEquals(label, step.found, game.found)
                assertEquals(label, step.level, game.level)
                assertEquals(label, step.gained, game.livesGained)
                assertEquals(label, step.finished, game.finished)
            }
        }
    }

    @Test fun duoGamesMatchTheReference() {
        for (case in ModeVectors.duo) {
            val game = DuoGame(case.seed)
            assertEquals(case.duos, game.duos.map { it.id })
            for (step in case.steps) {
                val (kind, at) = step.action.split("@").let { it[0] to it[1].toInt() }
                val duo = game.duos[minOf(game.round, game.duos.size - 1)]
                when (kind) {
                    "a" -> game.answer(duo.first.word, at)
                    "b" -> game.answer(duo.second.word, at)
                    "ko" -> game.answer("ZZZ", at)
                    "skip" -> game.skip(at)
                    else -> game.next(at)
                }
                val label = "graine ${case.seed}, ${step.action}"
                assertEquals(label, step.round, game.round)
                assertEquals(label, step.found, game.wordsFound)
                assertEquals(label, step.solved, game.solved)
                assertEquals(label, step.errors, game.errors)
                assertEquals(label, step.playMs, game.playMs(at))
                assertEquals(label, step.score, game.score(at))
                assertEquals(label, step.finished, game.finished)
            }
        }
    }
}

class SprintTest {
    private fun right(game: SprintGame, at: Int) = game.answer(game.card!!.wordFull, at)

    @Test fun comboGrowsToFiveThenWrongAnswerResetsIt() {
        val game = SprintGame(11uL)
        val multipliers = (1..7).map { (right(game, it * 1000) as SprintGame.Outcome.Right).multiplier }
        assertEquals(listOf(1, 2, 3, 4, 5, 5, 5), multipliers)
        assertEquals(7, game.bestCombo)
        assertEquals(SprintGame.Outcome.Wrong, game.answer("PASLEMOT", 8000))
        assertEquals(0, game.streak); assertEquals(1, game.multiplier)
        assertEquals(1, (right(game, 9000) as SprintGame.Outcome.Right).multiplier)
    }

    @Test fun pointsAreDifficultyTimesCombo() {
        val game = SprintGame(3uL)
        var expected = 0
        repeat(12) { index ->
            val card = game.card!!
            val outcome = right(game, index * 500) as SprintGame.Outcome.Right
            assertEquals(SprintGame.basePoints(card.difficulty) * minOf(5, index + 1), outcome.points)
            expected += outcome.points
        }
        assertEquals(expected, game.score)
    }

    @Test fun passingCostsFiveSecondsAndTheCombo() {
        val game = SprintGame(5uL)
        right(game, 1000); right(game, 2000)
        val before = game.card
        game.skip(3000)
        assertNotEquals(before?.id, game.card?.id)
        assertEquals(0, game.streak); assertEquals(1, game.skips)
        assertEquals(90_000 - 3000 - 5000, game.remainingMs(3000))
    }

    @Test fun theGameEndsAtZeroAndRefusesLateAnswers() {
        val game = SprintGame(8uL)
        assertFalse(game.tick(89_999))
        assertTrue(game.tick(90_000))
        assertTrue(game.finished)
        assertEquals(SprintGame.Outcome.Over, game.answer(game.card!!.wordFull, 90_500))
        assertEquals(0, game.found)
    }

    @Test fun timeSpentInTheBackgroundStillCounts() {
        // The screen measures time on a clock that keeps running while the phone sleeps:
        // coming back after the end can only show the end.
        val game = SprintGame(9uL)
        right(game, 10_000)
        assertEquals(SprintGame.Outcome.Over, game.answer(game.card!!.wordFull, 95_000))
        assertTrue(game.finished); assertEquals(1, game.found)
    }

    @Test fun aGameNeverShowsTheSameWordTwice() {
        val game = SprintGame(21uL)
        repeat(150) { right(game, 0) }
        assertEquals(game.used.size, game.used.toSet().size)
    }

    @Test fun accuracyCountsCheckedAnswers() {
        val game = SprintGame(4uL)
        right(game, 0); right(game, 0); right(game, 0); game.answer("NON", 0); game.skip(0)
        assertEquals(75, game.accuracy)
    }

    @Test fun aSavedGameResumesIdentically() {
        val game = SprintGame(31uL)
        right(game, 1000); game.answer("NON", 2000)
        val copy = ProgressJson.decodeFromString(SprintGame.serializer(), ProgressJson.encodeToString(SprintGame.serializer(), game))
        assertEquals(game.card, copy.card); assertEquals(game.score, copy.score); assertEquals(game.used, copy.used)
        right(game, 3000); right(copy, 3000)
        assertEquals(game.card, copy.card)
    }
}

class SurvivalTest {
    private fun right(game: SurvivalGame) = game.answer(game.card!!.wordFull)

    @Test fun threeMistakesEndTheGame() {
        val game = SurvivalGame(1uL)
        assertEquals(SurvivalGame.Outcome.Wrong(2), game.answer("NON"))
        game.skip()
        assertEquals(1, game.lives); assertFalse(game.finished)
        assertEquals(SurvivalGame.Outcome.Wrong(0), game.answer("NON"))
        assertTrue(game.finished); assertEquals(3, game.mistakes)
        assertEquals(SurvivalGame.Outcome.Over, game.answer(game.card!!.wordFull))
    }

    @Test fun everyTenthWordGivesALifeBackButNeverAFourth() {
        val game = SurvivalGame(2uL)
        repeat(10) { right(game) }
        assertEquals(3, game.lives); assertEquals(0, game.livesGained)
        game.answer("NON")
        repeat(9) { right(game) }
        assertEquals(2, game.lives)
        assertEquals(SurvivalGame.Outcome.Right(lifeGained = true), right(game))
        assertEquals(3, game.lives)
    }

    @Test fun levelsRiseEveryFiveWordsAndHardWordsComeLater() {
        val game = SurvivalGame(6uL)
        val seen = mutableListOf<Pair<Int, Difficulty>>()
        repeat(60) { seen += game.level to game.card!!.difficulty; right(game) }
        assertEquals(13, game.level)
        assertTrue(seen.filter { it.first == 1 }.all { it.second == Difficulty.EASY })
        assertTrue(seen.filter { it.first <= 2 }.none { it.second == Difficulty.HARD })
        val late = seen.filter { it.first >= 7 }
        assertTrue(late.count { it.second == Difficulty.HARD } > late.size / 2)
    }

    @Test fun theDifficultyTableAddsUpAndHardensSteadily() {
        for (row in SurvivalGame.LEVELS) assertEquals(100, row.sum())
        val hard = SurvivalGame.LEVELS.map { it[2] }
        assertEquals(hard.sorted(), hard)
        assertEquals(SurvivalGame.LEVELS.last(), SurvivalGame.weights(40))
    }

    @Test fun abandonKeepsTheRun() {
        val game = SurvivalGame(3uL)
        right(game); right(game)
        game.abandon()
        assertTrue(game.finished); assertEquals(2, game.found)
    }
}

class DuoTest {
    @Test fun everyDuoIsValid() {
        val words = mutableSetOf<String>()
        val sets = mutableSetOf<String>()
        assertTrue("au moins 30 duos", DuoBank.all.size >= 30)
        for (duo in DuoBank.all) {
            val a = WordEngine.normalize(duo.first.word); val b = WordEngine.normalize(duo.second.word)
            assertNotEquals(duo.id, a, b)
            assertEquals(duo.id, WordEngine.consonants(duo.first.word), WordEngine.consonants(duo.second.word))
            assertTrue(duo.id, WordEngine.validWord(duo.first.word) && WordEngine.validWord(duo.second.word))
            assertNotEquals(duo.id, duo.first.hint, duo.second.hint)
            for (word in listOf(duo.first, duo.second)) {
                assertFalse(duo.id, WordEngine.normalize(word.hint).contains(WordEngine.normalize(word.word)))
            }
            assertTrue("doublon ${duo.id}", words.add(a) && words.add(b))
            assertTrue("consonnes déjà jouées ${duo.id}", sets.add(duo.consonants))
        }
    }

    @Test fun eachAnswerFillsItsOwnClue() {
        val game = DuoGame(12uL)
        val duo = game.duo!!
        assertEquals(DuoGame.Outcome.SECOND, game.answer(duo.second.word.lowercase(), 1000))
        assertEquals(DuoGame.Outcome.ALREADY, game.answer(duo.second.word, 2000))
        assertEquals(0, game.errors)
        assertEquals(DuoGame.Outcome.WRONG, game.answer("XYZ", 2500))
        assertEquals(DuoGame.Outcome.FIRST, game.answer(duo.first.word, 3000))
        assertTrue(game.roundComplete)
        assertEquals(DuoGame.Outcome.OVER, game.answer(duo.first.word, 3500))
    }

    @Test fun aRoundCanBePassedAndTheGameGoesOn() {
        val game = DuoGame(13uL)
        game.answer(game.duo!!.first.word, 1000)
        game.skip(2000)
        assertTrue(game.roundComplete)
        game.next(5000)
        assertEquals(1, game.round)
        // The three seconds spent on the revealed answer are not counted.
        assertEquals(2000, game.playMs(5000))
        assertEquals(1, game.wordsFound); assertEquals(0, game.solved)
    }

    @Test fun aPerfectGameScoresEveryBonus() {
        val game = DuoGame(14uL)
        repeat(DuoGame.ROUNDS) { index ->
            val duo = game.duo!!
            game.answer(duo.first.word, index * 10_000 + 1000)
            game.answer(duo.second.word, index * 10_000 + 2000)
            game.next(index * 10_000 + 2000)
        }
        assertTrue(game.finished); assertTrue(game.perfect)
        assertEquals(5, game.solved); assertEquals(10, game.wordsFound)
        // 42 s of play: 1 000 + 250 + (300 − 42) × 10 / 10.
        assertEquals(42_000, game.playMs(99_000))
        assertEquals(1000 + 250 + 258, game.score(99_000))
        assertEquals(1, game.add[ModeStat.PERFECT])
        assertEquals(5, game.add[ModeStat.DUOS_PLAYED])
    }

    @Test fun theScoreNeverGoesNegativeAndAbandonCountsEveryRound() {
        val game = DuoGame(15uL)
        repeat(20) { game.answer("FAUX", 1000) }
        assertEquals(0, game.score(2000))
        game.abandon(3000)
        assertTrue(game.finished)
        assertEquals(5, game.add[ModeStat.DUOS_PLAYED]); assertEquals(0, game.add[ModeStat.DUOS_SOLVED])
    }

    @Test fun fiveDifferentDuosAvoidingRecentOnes() {
        val first = DuoGame(16uL).duos.map { it.id }
        assertEquals(5, first.toSet().size)
        val next = DuoGame(16uL, recent = first).duos.map { it.id }
        assertTrue(next.none { it in first })
    }
}

class CatalogueTest {
    @Test fun theCatalogueHasHundredsOfCheckedCards() {
        val all = ModeCatalogue.cards
        assertTrue(all.size >= 300)
        assertEquals(all.size, all.map { it.id }.toSet().size)
        assertEquals("un mot par carte", all.size, all.map { WordEngine.normalize(it.wordFull) }.toSet().size)
        val daily = DailyPool.all.map { WordEngine.normalize(it.wordFull) }.toSet()
        for (card in all) {
            assertTrue(card.id, WordEngine.validWord(card.wordFull))
            assertTrue(card.id, card.hint.length in 8..120)
            assertFalse("${card.id} : l’indice donne la réponse", WordEngine.normalize(card.hint).contains(WordEngine.normalize(card.wordFull)))
            assertFalse("${card.id} : réservé au mot du jour", WordEngine.normalize(card.wordFull) in daily)
        }
        for (level in Difficulty.entries) assertTrue(all.count { it.difficulty == level } >= 60)
    }

    @Test fun extraCardsAreClassiqueCardsToo() {
        assertTrue(ExtraCards.all.all { it.id.startsWith("seed-") && it.status == ReviewStatus.APPROVED })
    }
}

class ModeRecordsTest {
    @Test fun recordsOnlyGrowAndReportWhatWasBeaten() {
        var progress = Progress()
        val (first, beaten) = progress.recordingMode(PlayMode.SPRINT, mapOf("score" to 120, "words" to 6, "combo" to 4), mapOf("games" to 1), "A")
        assertEquals(setOf("score", "words", "combo"), beaten)
        progress = first
        val (second, again) = progress.recordingMode(PlayMode.SPRINT, mapOf("score" to 90, "words" to 8, "combo" to 2), mapOf("games" to 1), "A")
        assertEquals(setOf("words"), again)
        val records = second.records(PlayMode.SPRINT)
        assertEquals(120, records.best("score")); assertEquals(8, records.best("words")); assertEquals(2, records.total("games"))
    }

    @Test fun twoPhonesPlayingOfflineKeepEveryGame() {
        val cloud = Progress(username = "Lou").recordingMode(PlayMode.SURVIVAL, mapOf("words" to 12, "level" to 3), mapOf("games" to 1), "iphone").first
        // Both phones start from the cloud copy, then play offline.
        val iphone = cloud.recordingMode(PlayMode.SURVIVAL, mapOf("words" to 20, "level" to 5), mapOf("games" to 1), "iphone").first
        val android = cloud.recordingMode(PlayMode.SURVIVAL, mapOf("words" to 15, "level" to 4), mapOf("games" to 1), "android").first
            .recordingMode(PlayMode.SURVIVAL, mapOf("words" to 2, "level" to 1), mapOf("games" to 1), "android").first
        for (merged in listOf(iphone.merged(android), android.merged(iphone), iphone.merged(android).merged(android).merged(iphone))) {
            val records = merged.records(PlayMode.SURVIVAL)
            assertEquals(20, records.best("words")); assertEquals(5, records.best("level"))
            assertEquals(4, records.total("games"))
        }
    }

    @Test fun recordsTravelInTheIphoneFormat() {
        val progress = Progress(username = "Lou").recordingMode(PlayMode.DUO, mapOf("score" to 900), mapOf("games" to 1, "perfect" to 0, "duosSolved" to 3, "duosPlayed" to 5), "d1").first
        val json = progress.toJson()
        assertTrue(json.contains("\"modes\":{\"duo\":{\"best\":{\"score\":900},\"counts\":{\"games\":{\"d1\":1}"))
        assertEquals(progress, Progress.fromJson(json))
        // An older copy without records still reads, and the records survive a merge with it.
        val old = Progress.fromJson("{\"username\":\"Lou\",\"attempts\":[],\"recentCards\":[],\"submissions\":[],\"dailyStarted\":{},\"dailyStartedAt\":{}}")
        assertEquals(null, old.modes)
        assertEquals(900, old.merged(progress).records(PlayMode.DUO).best("score"))
        assertEquals(900, progress.merged(old).records(PlayMode.DUO).best("score"))
    }

    @Test fun modeGamesNeverTouchTheOfficialScore() {
        val progress = Progress().recordingMode(PlayMode.SPRINT, mapOf("score" to 5000), mapOf("games" to 1), "A").first
        assertEquals(0, progress.score); assertTrue(progress.attempts.isEmpty()); assertEquals(0, progress.dailyWins)
    }
}
