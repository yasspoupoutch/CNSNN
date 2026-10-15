package com.poupoutch.cnsnn.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ChallengeTest {
    private val hour = 3_600_000L

    @Test fun drawMatchesTheReference() {
        for (item in ModeVectors.challenge) assertEquals("graine ${item.seed}", item.cards, ChallengeRules.draw(item.seed, item.recent))
    }

    @Test fun twoEasyTwoMediumOneHardDistinctPublicWords() {
        for (seed in listOf(1uL, 2uL, 3uL, 99uL, 12345uL)) {
            val ids = ChallengeRules.draw(seed)
            assertEquals(5, ids.toSet().size)
            val cards = ChallengeRules.cards(ids)!!
            assertEquals(listOf(Difficulty.EASY, Difficulty.EASY, Difficulty.MEDIUM, Difficulty.MEDIUM, Difficulty.HARD), cards.map { it.difficulty })
        }
        assertNull(ChallengeRules.cards(listOf("inconnu", "a", "b", "c", "d")))
    }

    @Test fun gameCountsErrorsAndSkipsAndAddsTwentySecondsPerSkip() {
        val game = ChallengeGame(ChallengeRules.cards(ChallengeRules.draw(7uL))!!)
        assertEquals(ChallengeGame.Outcome.WRONG, game.answer("ZZZ"))
        assertEquals(ChallengeGame.Outcome.RIGHT, game.answer(game.card!!.wordFull))
        game.skip()
        while (true) { val card = game.card ?: break; game.answer(card.wordFull) }
        assertTrue(game.finished)
        assertEquals(ChallengeGame.Outcome.OVER, game.answer("X"))
        assertEquals(4, game.found); assertEquals(1, game.skips); assertEquals(1, game.errors)
        assertEquals(80_000L, game.scoreMs(60_000))
    }

    private fun challenge(from: Challenge.Side = Challenge.Side("alice", "Alice", startedMs = 0), to: Challenge.Side = Challenge.Side("bob", "Bob")) =
        Challenge("c", emptyList(), 0, from, to)

    @Test fun bestTimeWinsThenFewerErrorsThenDraw() {
        val c = challenge(Challenge.Side("alice", "Alice", 0, 60_000, skips = 1, errors = 0), Challenge.Side("bob", "Bob", 1_000, 71_000, skips = 0, errors = 5))
        assertEquals(Challenge.Result.WON, c.result("bob", 2 * hour))
        assertEquals(Challenge.Result.LOST, c.result("alice", 2 * hour))
        val tie = c.copy(to = c.to.copy(finishedMs = 81_000))
        assertEquals(Challenge.Result.WON, tie.result("alice", 0))
        assertEquals(Challenge.Result.DRAW, tie.copy(to = tie.to.copy(errors = 0)).result("bob", 0))
    }

    @Test fun statesWhileOpen() {
        var c = challenge()
        assertEquals(Challenge.State.YourTurn, c.state("bob", hour))
        assertEquals(Challenge.State.Playing, c.state("alice", hour))
        c = c.copy(from = c.from.copy(finishedMs = 90_000))
        assertEquals(Challenge.State.Waiting, c.state("alice", hour))
        c = c.copy(to = c.to.copy(startedMs = 2 * hour))
        assertEquals(Challenge.State.Playing, c.state("bob", 2 * hour))
    }

    @Test fun deadlines() {
        var c = challenge(from = Challenge.Side("alice", "Alice", 0, 90_000))
        assertNull(c.result("alice", 47 * hour))
        assertEquals(Challenge.State.Over(Challenge.Result.EXPIRED), c.state("alice", 48 * hour))
        c = c.copy(to = c.to.copy(startedMs = 10 * hour))
        assertNull(c.result("alice", 49 * hour))
        assertEquals(Challenge.Result.WON, c.result("alice", 50 * hour))
        assertEquals(Challenge.Result.LOST, c.result("bob", 50 * hour))
        assertEquals(Challenge.Result.EXPIRED, c.copy(from = c.from.copy(finishedMs = null)).result("alice", 50 * hour))
    }

    @Test fun tallyPerFriend() {
        val won = challenge(Challenge.Side("alice", "Alice", 0, 50_000), Challenge.Side("bob", "Bob", 0, 60_000))
        val lost = won.copy(from = won.from.copy(finishedMs = 70_000))
        val other = won.copy(to = won.to.copy(uid = "carol"))
        val open = won.copy(to = won.to.copy(finishedMs = null))
        val all = listOf(won, lost, other, open)
        assertEquals(ChallengeTally(1, 1), ChallengeTally.of(all, "alice", "bob", hour))
        assertEquals(ChallengeTally(1, 1), ChallengeTally.of(all, "bob", "alice", hour))
        assertEquals(ChallengeTally(2, 1), ChallengeTally.of(all, "alice", now = hour))
        assertEquals("2 victoires · 1 défaite", ChallengeTally(2, 1).label)
        assertEquals("0 victoire · 0 défaite · 1 égalité", ChallengeTally(0, 0, 1).label)
        assertNull(ChallengeTally().label)
    }

    @Test fun formats() {
        assertEquals("1:58", ChallengeFormat.time(118_400))
        assertEquals("12:04", ChallengeFormat.time(724_000))
        assertEquals("31 h", ChallengeFormat.left(31 * hour + 5))
        assertEquals("45 min", ChallengeFormat.left(45 * 60_000L))
    }
}
