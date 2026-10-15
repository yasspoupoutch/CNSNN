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

    @Test fun idsStartWithTheTimeSoTheLatestComeAfterACursor() {
        assertEquals("0000000001234-abc", ChallengeRules.newId(1234, "abc"))
        val now = 1_760_000_000_000L
        assertEquals("1760000000000-x", ChallengeRules.newId(now, "x"))
        assertEquals((now - 52 * hour).toString(), ChallengeRules.recentFromId(now))
        assertTrue(ChallengeRules.newId(now - 51 * hour, "zz") > ChallengeRules.recentFromId(now))
        assertTrue(ChallengeRules.newId(now - 53 * hour, "zz") < ChallengeRules.recentFromId(now))
        assertEquals("0000000000000", ChallengeRules.recentFromId(0))
    }

    @Test fun alertsForANewChallengeAndForAResultOnlyOnce() {
        val sent = Challenge("c", emptyList(), 0, Challenge.Side("alice", "Alice", startedMs = 0, finishedMs = 60_000), Challenge.Side("bob", "Bob"))
        // Bob is challenged; Alice (who sent it) gets nothing yet.
        val forBob = ChallengeAlerts.pending(listOf(sent), "bob", hour, emptySet())
        assertEquals(listOf("c.new"), forBob.map { it.key })
        assertEquals("Alice vous a défié !", forBob[0].title)
        assertEquals("Mêmes 5 mots, le plus rapide gagne. Plus que 47 h pour jouer.", forBob[0].body)
        assertTrue(ChallengeAlerts.pending(listOf(sent), "alice", hour, emptySet()).isEmpty())
        assertTrue(ChallengeAlerts.pending(listOf(sent), "bob", hour, setOf("c.new")).isEmpty())
        // Bob finished after Alice: Alice hears the result, Bob saw it on screen.
        val done = sent.copy(to = Challenge.Side("bob", "Bob", startedMs = 2 * hour, finishedMs = 2 * hour + 90_000))
        val forAlice = ChallengeAlerts.pending(listOf(done), "alice", 3 * hour, emptySet())
        assertEquals(listOf("c.done"), forAlice.map { it.key })
        assertEquals("Victoire contre Bob !", forAlice[0].title)
        assertEquals("Votre chrono : 1:00 · Bob : 1:30", forAlice[0].body)
        assertTrue(ChallengeAlerts.pending(listOf(done), "bob", 3 * hour, emptySet()).isEmpty())
        // Lost and draw titles; an expired challenge says nothing.
        val slow = done.copy(to = Challenge.Side("bob", "Bob", startedMs = 2 * hour, finishedMs = 2 * hour + 30_000))
        assertEquals("Défaite contre Bob", ChallengeAlerts.all(listOf(slow), "alice", 3 * hour).single().title)
        val tie = done.copy(to = Challenge.Side("bob", "Bob", startedMs = 2 * hour, finishedMs = 2 * hour + 60_000))
        assertEquals("Égalité avec Bob", ChallengeAlerts.all(listOf(tie), "alice", 3 * hour).single().title)
        assertTrue(ChallengeAlerts.all(listOf(sent), "alice", 49 * hour).isEmpty())
        assertTrue(ChallengeAlerts.all(listOf(sent), "bob", 49 * hour).isEmpty())
        assertTrue(ChallengeAlerts.all(listOf(sent), "carol", hour).isEmpty())
    }

    /** The phone keeps the old challenges (frozen after 50 h) and reads only the recent ones. */
    @Test fun mergeKeepsFrozenChallengesAndTakesTheRecentOnes() {
        val now = 1_800_000_000_000L
        fun make(hoursAgo: Int, finished: Boolean = false): Challenge {
            val created = now - hoursAgo * hour
            return Challenge(ChallengeRules.newId(created, "r$hoursAgo"), emptyList(), created,
                Challenge.Side("alice", "Alice", startedMs = created, finishedMs = if (finished) created + 60_000 else null), Challenge.Side("bob", "Bob"))
        }
        val old = make(100, true); val recentStale = make(3); val recentFresh = make(3, true); val gone = make(10); val new = make(1)
        val merged = ChallengeRules.merge(listOf(old, recentStale, gone), listOf(recentFresh, new), now)
        // The recent list replaces what was cached for that period (a deleted one disappears).
        assertEquals(listOf(new.id, recentFresh.id, old.id), merged.map { it.id })
        assertTrue(merged[1].from.finished)
    }

    /** Background checks: every 30 minutes, none at night, none just after the app read the challenges. */
    @Test fun backgroundChecksArePaced() {
        val paris = java.time.ZoneId.of("Europe/Paris")
        val evening = java.time.ZonedDateTime.of(2026, 10, 15, 21, 0, 0, 0, paris).toInstant().toEpochMilli()
        assertEquals(evening + 30 * 60_000, ChallengeRules.nextCheckMs(evening, paris))
        val lateNight = java.time.ZonedDateTime.of(2026, 10, 15, 23, 45, 0, 0, paris).toInstant().toEpochMilli()
        assertEquals(java.time.ZonedDateTime.of(2026, 10, 16, 7, 0, 0, 0, paris).toInstant().toEpochMilli(), ChallengeRules.nextCheckMs(lateNight, paris))
        val night = java.time.ZonedDateTime.of(2026, 10, 16, 3, 0, 0, 0, paris).toInstant().toEpochMilli()
        assertTrue(!ChallengeRules.shouldCheck(night, null, paris))
        assertTrue(ChallengeRules.shouldCheck(evening, null, paris))
        assertTrue(!ChallengeRules.shouldCheck(evening, evening - 5 * 60_000, paris))
        assertTrue(ChallengeRules.shouldCheck(evening, evening - 20 * 60_000, paris))
    }
}
