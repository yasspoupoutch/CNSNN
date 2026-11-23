package com.poupoutch.cnsnn.core

import kotlinx.serialization.Serializable

// Tournoi de la semaine: everyone can sign up until Monday 9 h (Paris, winter time: 08:00 UTC). Then a
// knockout bracket, one round a day: each player of a match plays the same 5 words whenever they want
// within the 24 hours, the best time goes through (+20 s per word passed), the other one is out.
// No server: the bracket follows from the players signed up (a draw seeded by the week) and from the
// runs stamped by Firestore (tournaments/{week}/…, see Firebase/firestore.rules). Same as Tournament.swift.

object TournamentRules {
    const val MAX_PLAYERS = 64
    /** From this tournament on, everyone plays every round: neighbours meet, and with an odd number the
     *  last match is played by 3 (the fastest goes through). Before: a full bracket of 2, 4, 8… with byes.
     *  A date, not a version: every phone must draw the same bracket. */
    const val EVERYONE_PLAYS_FROM = "2026-12-07"
    fun everyonePlays(week: String): Boolean = week >= EVERYONE_PLAYS_FROM
    const val DAY_MS = 86_400_000L
    /** Sign-ups close, and the first round opens, on Monday at 08:00 UTC. */
    const val START_HOUR_MS = 8 * 3_600_000L

    /** A week's id: its Monday, "2026-11-16". */
    fun deadlineMs(week: String): Long? {
        val parts = week.split("-").mapNotNull { it.toIntOrNull() }
        if (parts.size != 3 || parts[1] !in 1..12 || parts[2] !in 1..31) return null
        val day = daysFromCivil(parts[0], parts[1], parts[2])
        if (weekday(day) != 0L) return null
        return day * DAY_MS + START_HOUR_MS
    }
    /** The tournament whose sign-ups are open now. */
    fun nextWeek(nowMs: Long): String {
        val day = Math.floorDiv(nowMs - START_HOUR_MS, DAY_MS)
        var monday = day - weekday(day)
        if (monday * DAY_MS + START_HOUR_MS <= nowMs) monday += 7
        return civil(monday)
    }
    /** The tournament under way (or just over): the one that started last Monday. */
    fun currentWeek(nowMs: Long): String =
        civil(Math.floorDiv((deadlineMs(nextWeek(nowMs)) ?: 0L) - START_HOUR_MS, DAY_MS) - 7)
    /** Round r (from 1) is open for 24 hours, the first one from the Monday deadline. */
    fun roundStartMs(week: String, round: Int): Long? = deadlineMs(week)?.let { it + (round - 1) * DAY_MS }
    fun roundEndMs(week: String, round: Int): Long? = deadlineMs(week)?.let { it + round * DAY_MS }
    /** 2 players: 1 round (the final); up to 64: 6 rounds. Everyone playing (from [EVERYONE_PLAYS_FROM]):
     *  3 players, one match of 3; 10 players, 5 matches, then 2 (one of 3), then the final. */
    fun rounds(players: Int, week: String = ""): Int {
        val count = minOf(players, MAX_PLAYERS)
        if (count < 2) return 0
        var size = 1
        var rounds = 0
        if (everyonePlays(week)) while (size * 2 <= count) { size *= 2; rounds++ }
        else while (size < count) { size *= 2; rounds++ }
        return rounds
    }
    /** The round open at this moment, if any. */
    fun round(week: String, players: Int, nowMs: Long): Int? {
        val start = deadlineMs(week) ?: return null
        if (nowMs < start) return null
        val round = ((nowMs - start) / DAY_MS).toInt() + 1
        return if (round <= rounds(players, week)) round else null
    }
    /** The words of a round, drawn by the first player who starts it (then kept in Firestore). */
    fun draw(week: String, round: Int): List<String> = ChallengeRules.draw(seed("$week#$round"))

    /** Every tournament week from the first one to the one open for sign-ups (to delete an account). */
    fun weeks(untilMs: Long): List<String> {
        val first = deadlineMs("2026-11-09") ?: return emptyList()
        val last = deadlineMs(nextWeek(untilMs)) ?: return emptyList()
        return (first..last step 7 * DAY_MS).map { civil(Math.floorDiv(it, DAY_MS)) }
    }
    /** FNV-1a, 64 bits: the same seed on both platforms. */
    fun seed(text: String): ULong {
        var hash = 0xcbf29ce484222325uL
        for (byte in text.toByteArray(Charsets.UTF_8)) hash = (hash xor (byte.toUByte().toULong())) * 0x100000001b3uL
        return hash
    }

    // Calendar arithmetic on days since 1970-01-01 (a Thursday), so no time zone is involved.
    internal fun weekday(day: Long): Long = Math.floorMod(day + 3, 7L)
    internal fun daysFromCivil(y0: Int, m: Int, d: Int): Long {
        val y = (if (m <= 2) y0 - 1 else y0).toLong()
        val era = Math.floorDiv(y, 400L)
        val yoe = y - era * 400
        val doy = (153 * (m + (if (m > 2) -3 else 9)) + 2) / 5 + d - 1
        val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
    internal fun civil(days: Long): String {
        val z = days + 719_468
        val era = Math.floorDiv(z, 146_097L)
        val doe = z - era * 146_097
        val yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        val doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        val mp = (5 * doy + 2) / 153
        val d = doy - (153 * mp + 2) / 5 + 1
        val m = if (mp < 10) mp + 3 else mp - 9
        val y = yoe + era * 400 + (if (m <= 2) 1 else 0)
        return "%04d-%02d-%02d".format(y, m, d)
    }
}

@Serializable
data class TournamentPlayer(val uid: String, val name: String, val atMs: Long)

/** One player's 5 words in one round, timed by the server. */
@Serializable
data class TournamentRun(
    val uid: String,
    val round: Int,
    val startedMs: Long,
    val finishedMs: Long? = null,
    val skips: Int = 0,
    val errors: Int = 0,
) {
    val scoreMs: Long? get() = finishedMs?.let { it - startedMs + skips * ChallengeRules.SKIP_PENALTY_MS }
}

class TournamentBracket(val week: String, signedUp: List<TournamentPlayer>, runs: List<TournamentRun>, nowMs: Long) {
    sealed interface Slot {
        data class Player(val player: TournamentPlayer) : Slot
        /** Nobody: a bye, or a match where neither player played. */
        data object Empty : Slot
        /** Not known yet: the match before is still being played. */
        data object Pending : Slot
    }
    /**
     * One match: [c] is a third player when the round has an odd number of players (the fastest of the three
     * goes through). [from]: for each slot (a, b, then c), the match of the round before it comes from.
     */
    data class Match(val a: Slot, val b: Slot, val decided: Boolean = false, val winner: TournamentPlayer? = null,
                     val c: Slot? = null, val from: List<Int> = emptyList()) {
        val slots: List<Slot> get() = listOfNotNull(a, b, c)
        fun has(uid: String) = slots.any { (it as? Slot.Player)?.player?.uid == uid }
        fun opponent(uid: String): Slot = if ((a as? Slot.Player)?.player?.uid == uid) b else a
        /** The others of my match (one, or two in a match of 3). */
        fun opponents(uid: String): List<Slot> {
            val index = slots.indexOfFirst { (it as? Slot.Player)?.player?.uid == uid }
            return if (index < 0) slots else slots.filterIndexed { i, _ -> i != index }
        }
        /** Where the slot at this position comes from, as a previous-round match index. */
        fun source(position: Int): Int? = from.getOrNull(position)
    }

    /** The players in the draw: the first 64 signed up. */
    val players: List<TournamentPlayer>
    val rounds: List<List<Match>>

    init {
        val entrants = signedUp.sortedWith(compareBy({ it.atMs }, { it.uid })).take(TournamentRules.MAX_PLAYERS).toMutableList()
        val random = ModeRandom(TournamentRules.seed(week))
        for (i in entrants.size - 1 downTo 1) { val j = random.int(i + 1); val t = entrants[i]; entrants[i] = entrants[j]; entrants[j] = t }
        players = entrants
        val total = TournamentRules.rounds(entrants.size, week)
        val all = mutableListOf<List<Match>>()
        val byKey = runs.associateBy { "${it.round}_${it.uid}" }
        if (total > 0 && TournamentRules.everyonePlays(week)) {
            // Everyone plays every round: neighbours meet; with an odd number, the last match is played by 3.
            var slots: List<Slot> = entrants.map { Slot.Player(it) }
            for (round in 1..total) {
                val end = TournamentRules.roundEndMs(week, round) ?: 0L
                val count = slots.size / 2
                val matches = (0 until count).map { i ->
                    val three = i == count - 1 && slots.size % 2 == 1
                    val from = if (round == 1) emptyList() else if (three) listOf(2 * i, 2 * i + 1, 2 * i + 2) else listOf(2 * i, 2 * i + 1)
                    decide(Match(slots[2 * i], slots[2 * i + 1], c = if (three) slots[2 * i + 2] else null, from = from), round, end, nowMs, byKey)
                }
                all += matches
                slots = matches.map { next(it) }
            }
        } else if (total > 0) {
            val half = (1 shl total) / 2
            var current = (0 until half).map { k ->
                Match(Slot.Player(entrants[k]), if (k + half < entrants.size) Slot.Player(entrants[k + half]) else Slot.Empty)
            }
            for (round in 1..total) {
                val end = TournamentRules.roundEndMs(week, round) ?: 0L
                current = current.map { decide(it, round, end, nowMs, byKey) }
                all += current
                if (round == total) break
                val previous = current
                current = (previous.indices step 2).map { k -> Match(next(previous[k]), next(previous[k + 1]), from = listOf(k, k + 1)) }
            }
        }
        rounds = all
    }

    private fun next(match: Match): Slot = if (!match.decided) Slot.Pending else match.winner?.let { Slot.Player(it) } ?: Slot.Empty

    private fun decide(match: Match, round: Int, end: Long, now: Long, runs: Map<String, TournamentRun>): Match {
        if (match.slots.any { it is Slot.Pending }) return match
        val players = match.slots.mapNotNull { (it as? Slot.Player)?.player }
        // Nobody, or one player alone: decided at once.
        if (players.size < 2) return match.copy(decided = true, winner = players.firstOrNull())
        val scored = players.mapNotNull { p ->
            val run = runs["${round}_${p.uid}"] ?: return@mapNotNull null
            val finished = run.finishedMs ?: return@mapNotNull null
            if (finished <= end) p to run else null
        }
        // Everyone finished: no need to wait for the end of the day.
        if (scored.size < players.size && now < end) return match
        val best = scored.reduceOrNull { x, y -> if (better(x.second, y.second)) x else y }
        return match.copy(decided = true, winner = best?.first)
    }

    /** The match of the next round that match [index] of [round] leads to, and the positions of the others in it. */
    fun following(round: Int, index: Int): Pair<Match, List<Int>>? {
        if (round >= rounds.size) return null
        val match = rounds[round].firstOrNull { index in it.from } ?: return null
        return match to match.from.indices.filter { match.from[it] != index }
    }

    /** The champion, once the final is decided. */
    val champion: TournamentPlayer? get() = rounds.lastOrNull()?.firstOrNull()?.takeIf { it.decided }?.winner

    sealed interface Standing {
        /** Not in the draw (signed up too late, or not at all). */
        data object Out : Standing
        /** My match of this round: to play, or waiting for the other one / the end of the day. */
        data class InMatch(val round: Int, val match: Match) : Standing
        data class Through(val round: Int) : Standing
        data class Eliminated(val round: Int) : Standing
        data object Champion : Standing
    }

    fun standing(uid: String, nowMs: Long): Standing {
        if (players.none { it.uid == uid }) return Standing.Out
        rounds.forEachIndexed { index, matches ->
            val round = index + 1
            val match = matches.firstOrNull { it.has(uid) } ?: return Standing.Through(round)
            if (!match.decided) return Standing.InMatch(round, match)
            if (match.winner?.uid != uid) return Standing.Eliminated(round)
            if (round == rounds.size) return Standing.Champion
            // Through: shown on this round until the next one opens.
            if (nowMs < (TournamentRules.roundEndMs(week, round) ?: 0L)) return Standing.InMatch(round, match)
        }
        return Standing.Out
    }

    companion object {
        /** Best time, then fewer errors, then the first one to finish. */
        fun better(x: TournamentRun, y: TournamentRun): Boolean {
            val sx = x.scoreMs ?: Long.MAX_VALUE
            val sy = y.scoreMs ?: Long.MAX_VALUE
            if (sx != sy) return sx < sy
            if (x.errors != y.errors) return x.errors < y.errors
            if (x.finishedMs != y.finishedMs) return (x.finishedMs ?: Long.MAX_VALUE) < (y.finishedMs ?: Long.MAX_VALUE)
            return x.uid < y.uid
        }
    }
}

object TournamentFormat {
    /** A slot's name: the player, "personne", or where it comes from: "Gagnant de Léa / Sam", or
     *  "Gagnant du match 3" while that match is not known yet either. */
    fun slotName(bracket: TournamentBracket, round: Int, match: TournamentBracket.Match, position: Int): String {
        val slot = match.slots.getOrNull(position) ?: return ""
        return when (slot) {
            is TournamentBracket.Slot.Player -> slot.player.name
            TournamentBracket.Slot.Empty -> "personne"
            TournamentBracket.Slot.Pending -> {
                val source = match.source(position)
                val before = if (round > 1 && source != null) bracket.rounds.getOrNull(round - 2)?.getOrNull(source) else null
                if (before == null || source == null) "à venir"
                else {
                    val names = before.slots.mapNotNull { (it as? TournamentBracket.Slot.Player)?.player?.name }
                    if (names.size == before.slots.size) "Gagnant de " + names.joinToString(" / ") else "Gagnant du match ${source + 1}"
                }
            }
        }
    }

    /** "Finale", "Demi-finales", "Quarts de finale", "8es de finale", or "Tour 1". */
    fun roundName(round: Int, total: Int): String = when (total - round) {
        0 -> "Finale"
        1 -> "Demi-finales"
        2 -> "Quarts de finale"
        3 -> "8es de finale"
        4 -> "16es de finale"
        else -> "Tour $round"
    }
}

/**
 * Pictures only (screenshots): an invented tournament of 10, the second day under way. Round 1 is over
 * (I won mine), my match of the day is still to play, the others show who has played and who has not yet.
 */
object TournamentDemo {
    const val WEEK = TournamentRules.EVERYONE_PLAYS_FROM
    data class Data(val players: List<TournamentPlayer>, val runs: List<TournamentRun>, val nowMs: Long)
    fun make(me: String, name: String): Data {
        val begin = TournamentRules.deadlineMs(WEEK) ?: 0L
        val names = listOf("Léa", "Sam", "Nadji", "Inès", "Hugo", "Maya", "Yanis", "Zoé", "Tom")
        val players = listOf(TournamentPlayer(me, name, begin - 100_000)) +
            names.mapIndexed { i, n -> TournamentPlayer("demo-t$i", n, begin - 90_000 + i) }
        val order = TournamentBracket(WEEK, players, emptyList(), begin).players
        val runs = order.mapIndexed { index, p ->
            TournamentRun(p.uid, 1, begin + 3_600_000, begin + 3_600_000 + (if (p.uid == me) 24_000L else 31_000L + index * 2_300L),
                skips = if (index % 4 == 3) 1 else 0, errors = index % 3)
        }.toMutableList()
        val now = begin + TournamentRules.DAY_MS + 5 * 3_600_000L
        val bracket = TournamentBracket(WEEK, players, runs, now)
        bracket.rounds.getOrNull(1).orEmpty().filterNot { it.has(me) }.forEach { match ->
            val present = match.slots.mapNotNull { (it as? TournamentBracket.Slot.Player)?.player }
            present.firstOrNull()?.let { runs += TournamentRun(it.uid, 2, now - 3_000_000, now - 2_960_000) }
            if (present.size > 1) runs += TournamentRun(present[1].uid, 2, now - 20_000)
        }
        return Data(players, runs, now)
    }
}
