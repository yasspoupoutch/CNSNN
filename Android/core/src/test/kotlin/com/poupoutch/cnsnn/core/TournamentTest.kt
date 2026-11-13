package com.poupoutch.cnsnn.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TournamentTest {
    private val week = "2026-11-16"
    private val start = TournamentRules.deadlineMs(week)!!
    private val day = TournamentRules.DAY_MS
    private fun players(n: Int) = (1..n).map { TournamentPlayer("p%02d".format(it), "Joueur $it", it.toLong()) }

    @Test fun calendar() {
        assertEquals(1_794_816_000_000L, start) // Monday 16 Nov 2026, 08:00 UTC
        assertNull(TournamentRules.deadlineMs("2026-11-17"))
        assertEquals(week, TournamentRules.nextWeek(start - 1))
        assertEquals("2026-11-23", TournamentRules.nextWeek(start))
        assertEquals(week, TournamentRules.currentWeek(start))
        assertEquals(week, TournamentRules.currentWeek(start + 6 * day))
        assertEquals("2026-11-09", TournamentRules.currentWeek(start - 1))
        assertEquals("2027-01-04", TournamentRules.nextWeek(TournamentRules.deadlineMs("2026-12-28")!! + 1))
        assertEquals(listOf(0, 0, 1, 2, 2, 3, 4, 6, 6), listOf(0, 1, 2, 3, 4, 5, 9, 33, 200).map { TournamentRules.rounds(it) })
        assertEquals(2, TournamentRules.round(week, 5, start + day))
        assertNull(TournamentRules.round(week, 5, start + 3 * day))
    }

    @Test fun sameSeedAndDrawAsTheIPhone() {
        assertEquals(0xcbf29ce484222325uL, TournamentRules.seed(""))
        assertEquals(0xaf63dc4c8601ec8cuL, TournamentRules.seed("a"))
        val bracket = TournamentBracket(week, players(5), emptyList(), start)
        // Same values in Tests/Core/TournamentTests.swift.
        assertEquals(listOf("p02", "p05", "p03", "p04", "p01"), bracket.players.map { it.uid })
        assertEquals(0x472c22073cb5a8c4uL, TournamentRules.seed("$week#1"))
        assertEquals(5, TournamentRules.draw(week, 1).toSet().size)
    }

    @Test fun byesThenBestTimeGoesThrough() {
        val bracket0 = TournamentBracket(week, players(5), emptyList(), start)
        val order = bracket0.players
        assertEquals(3, bracket0.rounds.size)
        val first = bracket0.rounds[0]
        assertEquals(4, first.size)
        // 5 players in 8 places: 3 byes, through at once.
        assertEquals(3, first.count { it.decided })
        val (a, b) = order[0] to order[4]
        assertTrue(first[0].has(a.uid) && first[0].has(b.uid) && !first[0].decided)
        // a: 40 s + 1 pass = 60 s; b: 55 s.
        val runs = listOf(TournamentRun(a.uid, 1, start + 1_000, start + 41_000, skips = 1), TournamentRun(b.uid, 1, start + 5_000, start + 60_000))
        val after = TournamentBracket(week, players(5), runs, start + 100_000)
        assertEquals(b, after.rounds[0][0].winner)
        assertEquals(TournamentBracket.Slot.Player(b), after.rounds[1][0].a)
        assertEquals(TournamentBracket.Standing.Eliminated(1), after.standing(a.uid, start + 100_000))
        assertEquals(TournamentBracket.Standing.InMatch(1, after.rounds[0][0]), after.standing(b.uid, start + 100_000))
        assertTrue(after.standing(b.uid, start + day) is TournamentBracket.Standing.InMatch)
    }

    @Test fun nobodyPlayedOrOneFinishedAtTheEnd() {
        val order = TournamentBracket(week, players(4), emptyList(), start).players
        val runs = listOf(TournamentRun(order[0].uid, 1, start + 10, start + 50_000), TournamentRun(order[1].uid, 1, start + 10))
        val end = TournamentBracket(week, players(4), runs, start + day)
        assertEquals(order[0], end.rounds[0][0].winner)
        // order[1] and order[3] never finished: nobody goes through, order[0] wins the final alone.
        assertTrue(end.rounds[0][1].decided)
        assertNull(end.rounds[0][1].winner)
        assertEquals(TournamentBracket.Slot.Empty, end.rounds[1][0].b)
        assertEquals(order[0], end.champion)
        assertEquals(TournamentBracket.Standing.Champion, end.standing(order[0].uid, start + day))
        assertEquals(TournamentBracket.Standing.Out, end.standing("x", start + day))
    }

    @Test fun onlyTheFirst64() {
        val bracket = TournamentBracket(week, players(70), emptyList(), start)
        assertEquals(64, bracket.players.size)
        assertTrue(bracket.players.none { it.uid in listOf("p65", "p66", "p70") })
        assertEquals("Finale", TournamentFormat.roundName(6, 6))
        assertEquals("Tour 1", TournamentFormat.roundName(1, 6))
    }

    @Test fun weeksToDeleteWithTheAccount() {
        val monday16 = TournamentRules.deadlineMs("2026-11-16")!!
        assertEquals(listOf("2026-11-09", "2026-11-16"), TournamentRules.weeks(monday16 - 1))
        assertEquals(listOf("2026-11-09", "2026-11-16", "2026-11-23"), TournamentRules.weeks(monday16))
    }
}
