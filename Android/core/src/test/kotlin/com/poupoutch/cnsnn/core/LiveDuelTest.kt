package com.poupoutch.cnsnn.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveDuelTest {
    private fun duel(start: Long? = 10_000, from: LiveDuel.Side? = null, to: LiveDuel.Side? = null) =
        LiveDuel("d", emptyList(), 0, start, from ?: LiveDuel.Side("alice", "Alice"), to ?: LiveDuel.Side("bob", "Bob"))

    @Test fun waitingCountdownPlaying() {
        var d = duel(start = null, to = LiveDuel.Side("", ""))
        assertTrue(d.isOpen)
        assertEquals(LiveDuel.State.Waiting, d.state("alice", 1_000))
        assertFalse(d.joinClosed(14 * 60_000))
        assertTrue(d.joinClosed(15 * 60_000))
        d = d.copy(to = LiveDuel.Side("bob", "Bob"), startMs = 10_000)
        assertEquals(LiveDuel.State.Countdown, d.state("bob", 6_000))
        assertEquals(LiveDuel.State.Playing, d.state("bob", 10_000))
    }

    @Test fun firstToFinishWinsOnceTheOtherCanNoLongerCatchUp() {
        val d = duel(from = LiveDuel.Side("alice", "Alice", done = 5, skips = 1, finishedMs = 60_000))
        assertEquals(LiveDuel.State.Finished, d.state("alice", 60_000))
        assertNull(d.result("bob", 70_000))
        assertEquals(10_000L, d.leftToBeatMs("alice", 70_000))
        assertEquals(LiveDuel.Result.WON, d.result("alice", 80_001))
        assertEquals(LiveDuel.Result.LOST, d.result("bob", 80_001))
        val passed = d.copy(to = d.to.copy(skips = 1))
        assertEquals(LiveDuel.Result.WON, passed.result("alice", 60_001))
    }

    @Test fun bothFinishedBestScoreThenDraw() {
        val d = duel(from = LiveDuel.Side("alice", "Alice", done = 5, skips = 1, finishedMs = 60_000),
            to = LiveDuel.Side("bob", "Bob", done = 5, finishedMs = 75_000))
        assertEquals(LiveDuel.Result.WON, d.result("bob", 75_000))
        assertEquals(LiveDuel.Result.DRAW, d.copy(to = d.to.copy(finishedMs = 80_000)).result("alice", 80_000))
    }

    @Test fun quitLosesAndTimeLimit() {
        var d = duel()
        d = d.copy(to = d.to.copy(quit = true))
        assertEquals(LiveDuel.Result.WON, d.result("alice", 20_000))
        assertEquals(LiveDuel.Result.LOST, d.result("bob", 20_000))
        d = d.copy(from = d.from.copy(quit = true))
        assertEquals(LiveDuel.Result.DRAW, d.result("bob", 20_000))
        val slow = duel()
        assertNull(slow.result("alice", 10_000 + LiveDuelRules.MAX_MS - 1))
        assertEquals(LiveDuel.Result.DRAW, slow.result("alice", 10_000 + LiveDuelRules.MAX_MS))
    }

    @Test fun serverClock() {
        val clock = ServerClock()
        clock.learn(serverMs = 10_500, sentMs = 1_000, receivedMs = 1_400)
        assertEquals(9_300L, clock.offsetMs)
        assertEquals(11_300L, clock.now(2_000))
    }

    @Test fun inviteTextCarriesTheLink() {
        assertTrue(LiveDuelInvite.shareText("ABC234").contains("https://cnsnn-9ctosy.web.app/d/ABC234"))
    }
}
