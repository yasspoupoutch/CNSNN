package com.poupoutch.cnsnn.core

import kotlinx.serialization.Serializable

// Tournoi de la semaine: everyone can sign up until Monday 9 h (Paris, winter time: 08:00 UTC). Then a
// knockout bracket, one round a day: each player of a match plays the same 5 words whenever they want
// within the 24 hours, the best time goes through (+20 s per word passed), the other one is out.
// No server: the bracket follows from the players signed up (a draw seeded by the week) and from the
// runs stamped by Firestore (tournaments/{week}/…, see Firebase/firestore.rules). Same as Tournament.swift.

object TournamentRules {
    const val MAX_PLAYERS = 64
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
    /** 2 players: 1 round (the final); up to 64: 6 rounds. */
    fun rounds(players: Int): Int {
        var size = 1
        var rounds = 0
        while (size < minOf(players, MAX_PLAYERS)) { size *= 2; rounds++ }
        return if (players < 2) 0 else rounds
    }
    /** The round open at this moment, if any. */
    fun round(week: String, players: Int, nowMs: Long): Int? {
        val start = deadlineMs(week) ?: return null
        if (nowMs < start) return null
        val round = ((nowMs - start) / DAY_MS).toInt() + 1
        return if (round <= rounds(players)) round else null
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
    data class Match(val a: Slot, val b: Slot, val decided: Boolean = false, val winner: TournamentPlayer? = null) {
        fun has(uid: String) = (a as? Slot.Player)?.player?.uid == uid || (b as? Slot.Player)?.player?.uid == uid
        fun opponent(uid: String): Slot = if ((a as? Slot.Player)?.player?.uid == uid) b else a
    }

    /** The players in the draw: the first 64 signed up. */
    val players: List<TournamentPlayer>
    val rounds: List<List<Match>>

    init {
        val entrants = signedUp.sortedWith(compareBy({ it.atMs }, { it.uid })).take(TournamentRules.MAX_PLAYERS).toMutableList()
        val random = ModeRandom(TournamentRules.seed(week))
        for (i in entrants.size - 1 downTo 1) { val j = random.int(i + 1); val t = entrants[i]; entrants[i] = entrants[j]; entrants[j] = t }
        players = entrants
        val total = TournamentRules.rounds(entrants.size)
        val all = mutableListOf<List<Match>>()
        if (total > 0) {
            val half = (1 shl total) / 2
            var current = (0 until half).map { k ->
                Match(Slot.Player(entrants[k]), if (k + half < entrants.size) Slot.Player(entrants[k + half]) else Slot.Empty)
            }
            val byKey = runs.associateBy { "${it.round}_${it.uid}" }
            for (round in 1..total) {
                val end = TournamentRules.roundEndMs(week, round) ?: 0L
                current = current.map { decide(it, round, end, nowMs, byKey) }
                all += current
                if (round == total) break
                val previous = current
                current = (previous.indices step 2).map { k -> Match(next(previous[k]), next(previous[k + 1])) }
            }
        }
        rounds = all
    }

    private fun next(match: Match): Slot = if (!match.decided) Slot.Pending else match.winner?.let { Slot.Player(it) } ?: Slot.Empty

    private fun decide(match: Match, round: Int, end: Long, now: Long, runs: Map<String, TournamentRun>): Match {
        val a = match.a
        val b = match.b
        if (a is Slot.Pending || b is Slot.Pending) return match
        if (a is Slot.Empty && b is Slot.Empty) return match.copy(decided = true)
        if (a is Slot.Player && b is Slot.Empty) return match.copy(decided = true, winner = a.player)
        if (a is Slot.Empty && b is Slot.Player) return match.copy(decided = true, winner = b.player)
        val pa = (a as Slot.Player).player
        val pb = (b as Slot.Player).player
        fun score(p: TournamentPlayer): TournamentRun? {
            val run = runs["${round}_${p.uid}"] ?: return null
            val finished = run.finishedMs ?: return null
            return if (finished <= end) run else null
        }
        val ra = score(pa)
        val rb = score(pb)
        // Both finished: no need to wait for the end of the day.
        if (!(ra != null && rb != null) && now < end) return match
        val winner = when {
            ra != null && rb != null -> if (better(ra, rb)) pa else pb
            ra != null -> pa
            rb != null -> pb
            else -> null
        }
        return match.copy(decided = true, winner = winner)
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
