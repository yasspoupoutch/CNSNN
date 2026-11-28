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

    @Test fun everyonePlaysEveryRoundFromDecember() {
        val later = "2026-12-07"
        val begin = TournamentRules.deadlineMs(later)!!
        assertTrue(TournamentRules.everyonePlays(later))
        assertTrue(!TournamentRules.everyonePlays(week))
        assertEquals(listOf(0, 0, 1, 1, 2, 2, 3, 6, 6), listOf(0, 1, 2, 3, 4, 7, 10, 64, 200).map { TournamentRules.rounds(it, later) })
        // 14 players (too many for matches of 3 on Monday): 7 matches, then 3 (the last one by 3), then a
        // final by 3. Nobody alone.
        val bracket = TournamentBracket(later, players(14), emptyList(), begin)
        assertEquals(listOf(7, 3, 1), bracket.rounds.map { it.size })
        assertTrue(bracket.rounds[0].all { m -> m.c == null && m.slots.all { it is TournamentBracket.Slot.Player } && !m.decided })
        val semis = bracket.rounds[1]
        assertEquals(listOf(0, 1), semis[0].from)
        assertEquals(listOf(4, 5, 6), semis[2].from)
        assertEquals(TournamentBracket.Slot.Pending, semis[2].c)
        // Who's next: the winner of the two neighbours, named.
        val order = bracket.players
        assertEquals("Gagnant de ${order[2].name} / ${order[3].name}", TournamentFormat.slotName(bracket, 2, semis[0], 1))
        assertEquals("Gagnant du match 1", TournamentFormat.slotName(bracket, 3, bracket.rounds[2][0], 0))
        val (next, others) = bracket.following(1, 6)!!
        assertEquals(semis[2], next)
        assertEquals(listOf(0, 1), others)
        // Round 1 finished: the fastest of each match goes on, in the same order.
        val runs = (0 until 14).map { TournamentRun(order[it].uid, 1, begin + 1_000, begin + 30_000 + it * 1_000L) }
        val after = TournamentBracket(later, players(14), runs, begin + 100_000)
        assertEquals((0 until 14 step 2).map { order[it] }, after.rounds[0].map { it.winner })
        val three = after.rounds[1][2]
        assertEquals(listOf(order[8], order[10], order[12]).map { TournamentBracket.Slot.Player(it) }, three.slots)
        assertEquals(2, three.opponents(order[10].uid).size)
        // The match of 3: the fastest goes through, the two others are out.
        val second = runs + listOf(TournamentRun(order[8].uid, 2, begin + day, begin + day + 50_000),
            TournamentRun(order[10].uid, 2, begin + day, begin + day + 20_000), TournamentRun(order[12].uid, 2, begin + day, begin + day + 40_000))
        val later2 = TournamentBracket(later, players(14), second, begin + day + 60_000)
        assertEquals(order[10], later2.rounds[1][2].winner)
        assertEquals(TournamentBracket.Standing.Eliminated(2), later2.standing(order[12].uid, begin + day + 60_000))
        assertEquals(TournamentBracket.Slot.Player(order[10]), later2.rounds[2][0].c)
        // 3 players: one match of 3, which is the final.
        val small = TournamentBracket(later, players(3), emptyList(), begin)
        assertEquals(1, small.rounds.size)
        assertEquals(3, small.rounds[0][0].slots.size)
    }

    @Test fun matchesOf3OnMondayLeaveAPowerOf2() {
        val later = "2026-12-07"
        val begin = TournamentRules.deadlineMs(later)!!
        // Yasin's idea: 35 players, 16 matches on Monday (3 of them by 3), then 16 left: 8, 4, 2, 1.
        assertEquals(listOf(false, false, false, false, false, true, false, false, false, false, true, false, false, false, false, true),
            TournamentRules.firstRoundThrees(35))
        val bracket = TournamentBracket(later, players(35), emptyList(), begin)
        assertEquals(listOf(16, 8, 4, 2, 1), bracket.rounds.map { it.size })
        assertEquals(3, bracket.rounds[0].count { it.c != null })
        assertEquals(bracket.players.map { it.uid }, bracket.rounds[0].flatMap { m -> m.slots.map { (it as TournamentBracket.Slot.Player).player.uid } })
        assertTrue(bracket.rounds.drop(1).all { r -> r.all { it.c == null } })
        // 10 players: 4 matches (2 by 3), then 2, then the final. 3 players: one match of 3. 8 or 14: no change.
        assertEquals(listOf(4, 2, 1), TournamentBracket(later, players(10), emptyList(), begin).rounds.map { it.size })
        assertEquals(listOf(true), TournamentRules.firstRoundThrees(3))
        assertEquals(null, TournamentRules.firstRoundThrees(8))
        assertEquals(null, TournamentRules.firstRoundThrees(14))
        assertEquals(List(16) { true }, TournamentRules.firstRoundThrees(48))
        assertEquals(null, TournamentRules.firstRoundThrees(49))
    }

    @Test fun nobodyPlayedTheMatch() {
        val later = "2026-12-07"
        val begin = TournamentRules.deadlineMs(later)!!
        val order = TournamentBracket(later, players(4), emptyList(), begin).players
        // Round 1: match 2 played, match 1 not at all -> the first signed up of the two goes through.
        val first = listOf(order[2], order[3]).mapIndexed { i, p -> TournamentRun(p.uid, 1, begin, begin + 30_000 + i * 1_000L) }
        val after = TournamentBracket(later, players(4), first, begin + day)
        assertEquals(listOf(order[0], order[1]).minBy { it.atMs }, after.rounds[0][0].winner)
        // The final not played either: the best time of the round before (match 2's winner had one).
        val final = TournamentBracket(later, players(4), first, begin + 2 * day)
        assertEquals(order[2], final.rounds[1][0].winner)
        // Before December (old bracket): nobody goes through.
        assertEquals(null, TournamentBracket(week, players(4), emptyList(), start + day).rounds[0][0].winner)
    }

    @Test fun drawnLikeAFootballBracket() {
        val later = "2026-12-07"
        val begin = TournamentRules.deadlineMs(later)!!
        // 10 players: matches 1-2 on the left, 3-4 on the right (2 and 4 by 3), the final in the middle.
        val layout = TournamentLayout(TournamentBracket(later, players(10), emptyList(), begin), { if (it == 3) 84.0 else 60.0 }, 10.0)
        assertEquals(5, layout.columns)
        assertEquals(154.0, layout.height, 0.01)
        assertEquals(7, layout.nodes.size)
        fun at(r: Int, i: Int) = layout.node(r, i)!!
        assertEquals(TournamentLayout.Side.Left, at(1, 0).side); assertEquals(0, at(1, 0).column); assertEquals(30.0, at(1, 0).y, 0.01)
        assertEquals(112.0, at(1, 1).y, 0.01); assertEquals(84.0, at(1, 1).height, 0.01)
        assertEquals(TournamentLayout.Side.Right, at(1, 2).side); assertEquals(4, at(1, 3).column); assertEquals(30.0, at(1, 2).y, 0.01)
        assertEquals(1, at(2, 0).column); assertEquals(71.0, at(2, 0).y, 0.01)
        assertEquals(3, at(2, 1).column); assertEquals(71.0, at(2, 1).y, 0.01)
        assertEquals(TournamentLayout.Side.Center, at(3, 0).side); assertEquals(2, at(3, 0).column); assertEquals(77.0, at(3, 0).y, 0.01)
        // 64 players: 16 first matches each side, 11 columns. 2 players: the final alone.
        val big = TournamentLayout(TournamentBracket(later, players(64), emptyList(), begin), { 60.0 }, 10.0)
        assertEquals(11, big.columns); assertEquals(63, big.nodes.size)
        assertEquals(16, big.nodes.count { it.round == 1 && it.side == TournamentLayout.Side.Left })
        val two = TournamentLayout(TournamentBracket(later, players(2), emptyList(), begin), { 60.0 }, 10.0)
        assertEquals(1, two.columns); assertEquals(1, two.nodes.size)
        // The old format (byes) draws too.
        assertEquals(15, TournamentLayout(TournamentBracket(week, players(10), emptyList(), start), { 60.0 }, 10.0).nodes.size)
    }

    @Test fun remindersForTheTournament() {
        val demo = TournamentDemo.make("me", "Camille")
        val bracket = TournamentBracket(TournamentDemo.WEEK, demo.players, demo.runs, demo.nowMs)
        val begin = TournamentRules.deadlineMs(TournamentDemo.WEEK)!!
        val next = TournamentRules.nextWeek(demo.nowMs)
        val plan = TournamentReminders.plan(next, true, bracket, "me", demo.runs, demo.nowMs) { "demain" }
        assertEquals(listOf("start", "late", "round3"), plan.map { it.id })
        assertEquals(TournamentRules.deadlineMs(next), plan[0].atMs)
        assertEquals(begin + day + TournamentReminders.EVENING_AFTER_MS, plan[1].atMs)
        assertEquals("Finale du tournoi", plan[2].title)
        // Played and won: no evening reminder, the final is sure.
        val won = demo.runs + bracket.rounds[1][0].slots.mapNotNull { (it as? TournamentBracket.Slot.Player)?.player }.map {
            TournamentRun(it.uid, 2, demo.nowMs - 10_000, demo.nowMs - 10_000 + if (it.uid == "me") 20_000 else 40_000)
        }
        val later = demo.nowMs + 60_000
        val after = TournamentReminders.plan(next, false, TournamentBracket(TournamentDemo.WEEK, demo.players, won, later), "me", won, later) { "" }
        assertEquals(listOf("round3"), after.map { it.id })
        assertEquals("Qualifié : finale", after[0].title)
        // Out: nothing about this week.
        assertEquals(emptyList<TournamentReminders.Alert>(), TournamentReminders.plan(next, false, bracket, "nobody", demo.runs, demo.nowMs) { "" })
    }

    @Test fun demoForThePictures() {
        val demo = TournamentDemo.make("me", "Camille")
        val bracket = TournamentBracket(TournamentDemo.WEEK, demo.players, demo.runs, demo.nowMs)
        val standing = bracket.standing("me", demo.nowMs)
        assertTrue(standing is TournamentBracket.Standing.InMatch && standing.round == 2 && !standing.match.decided)
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
