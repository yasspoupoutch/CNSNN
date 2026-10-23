package com.poupoutch.cnsnn.core

import java.time.Instant

/** Official totals of one player (`leaderboard/{uid}`), only ever moved by the security rules' checks. */
data class LeaderboardEntry(
    val uid: String,
    val username: String,
    val played: Int,
    val wins: Int,
    val streak: Int,
    val bestStreak: Int,
    val bestTimeMs: Int?,
    val lastWinDay: String,
    /** This month's tally (DailyScore.Month); zeros for a line from before monthly totals. */
    val month: Int = 0,
    val monthSaved: Int = 0,
    val monthPlayed: Int = 0,
) {
    /** The stored streak only counts while the last win is today or yesterday. */
    fun currentStreak(at: Instant = Instant.now()): Int {
        val today = DailySchedule.key(at)
        return if (lastWinDay == today || lastWinDay == DailySchedule.shift(today, -1)) streak else 0
    }
    val successRate: Double get() = if (played == 0) 0.0 else wins.toDouble() / played
    val monthTally: DailyScore.Month get() = DailyScore.Month(month, monthSaved, monthPlayed)
    /** Played the Mot du jour in the month of `today` (yyyy-MM-dd). */
    fun playedMonth(today: String = DailySchedule.key()): Boolean = monthPlayed > 0 && month == DailyScore.monthIndex(today)
    /** This month's total time on `today`, null if not played this month (lower is better). */
    fun monthTotalMs(today: String = DailySchedule.key()): Int? =
        if (playedMonth(today)) DailyScore.monthTotal(monthSaved, DailyScore.dayOfMonth(today)) else null

    /**
     * The new totals after one more daily result: same arithmetic as the `tallies` rule in
     * Firebase/firestore.rules, which refuses anything else (`tallyMonth` included). Values only,
     * without the server time. The map replaces the whole line, so an old `points` field goes away.
     */
    companion object {
        fun tally(old: LeaderboardEntry?, uid: String, username: String, day: String, correct: Boolean, timeMs: Int, scoreMs: Int): Map<String, Any?> {
            val lastWin = old?.lastWinDay ?: ""
            val oldStreak = old?.streak ?: 0
            val laterWin = correct && day > lastWin
            val previous = lastWin.isNotEmpty() && DailySchedule.shift(day, -1) == lastWin
            val streak = if (laterWin) (if (previous) oldStreak + 1 else 1) else (if (!correct && day > lastWin) 0 else oldStreak)
            val best: Int? = if (correct) minOf(old?.bestTimeMs ?: timeMs, timeMs) else old?.bestTimeMs
            val month = DailyScore.tally(old?.monthTally ?: DailyScore.Month(), day, scoreMs)
            return mapOf(
                "uid" to uid, "username" to username, "played" to (old?.played ?: 0) + 1,
                "wins" to (old?.wins ?: 0) + (if (correct) 1 else 0), "streak" to streak, "bestStreak" to maxOf(old?.bestStreak ?: 0, streak),
                "bestTimeMs" to best, "lastWinDay" to if (laterWin) day else lastWin, "lastResult" to day,
                "month" to month.month, "monthSaved" to month.saved, "monthPlayed" to month.played, "monthRank" to month.rank,
            )
        }
    }
}

/**
 * Where a finished daily result stands among today's players, suspended ones left out as in the ranking.
 * [players] counts those who found the word (the lines of the day's ranking, so "3e sur 4" matches it);
 * [tried] counts everyone who played, found or not.
 */
data class DailyStanding(val rank: Int?, val players: Int, val beatenPercent: Int?, val tried: Int = players) {
    /** "Top X %" badge among the finders, rounded up to 1, 5, 10, 25 or 50 %. Null for number 1 and the slower half. */
    val topPercent: Int?
        get() {
            if (rank == null || rank <= 1 || players <= 1) return null
            val share = rank * 100.0 / players
            return listOf(1, 5, 10, 25, 50).firstOrNull { share <= it }
        }
}

/** One line of the friends ranking: the player's totals and today's Mot du jour, when played. */
data class FriendStanding(
    val uid: String,
    val username: String,
    /** This month's total time (DailyScore.monthTotal), null when not played this month. */
    val monthTotalMs: Int?,
    val streak: Int,
    val today: Attempt?,
    val todayWrong: Int? = null,
    /** Today's official time, the hint minute included. */
    val todayScoreMs: Int? = null,
    val todayHint: Boolean = false,
) {
    companion object {
        /** Found today first (fastest first), then the others by month total (lower first, none last), then by name. */
        fun ordered(rows: List<FriendStanding>): List<FriendStanding> = rows.sortedWith { a, b ->
            val fa = a.today?.correct == true
            val fb = b.today?.correct == true
            val sa = a.todayScoreMs ?: a.today?.timeMs ?: 0
            val sb = b.todayScoreMs ?: b.today?.timeMs ?: 0
            val ma = a.monthTotalMs ?: Int.MAX_VALUE
            val mb = b.monthTotalMs ?: Int.MAX_VALUE
            when {
                fa != fb -> if (fa) -1 else 1
                fa && sa != sb -> sa.compareTo(sb)
                ma != mb -> ma.compareTo(mb)
                else -> a.username.compareTo(b.username, ignoreCase = true)
            }
        }
    }
}
