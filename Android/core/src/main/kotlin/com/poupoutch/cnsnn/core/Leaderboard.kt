package com.poupoutch.cnsnn.core

import java.time.Instant

/** Official totals of one player (`leaderboard/{uid}`), only ever moved by the security rules' checks. */
data class LeaderboardEntry(
    val uid: String,
    val username: String,
    val points: Int,
    val played: Int,
    val wins: Int,
    val streak: Int,
    val bestStreak: Int,
    val bestTimeMs: Int?,
    val lastWinDay: String,
) {
    /** The stored streak only counts while the last win is today or yesterday. */
    fun currentStreak(at: Instant = Instant.now()): Int {
        val today = DailySchedule.key(at)
        return if (lastWinDay == today || lastWinDay == DailySchedule.shift(today, -1)) streak else 0
    }
    val successRate: Double get() = if (played == 0) 0.0 else wins.toDouble() / played

    /**
     * The new totals after one more daily result: same arithmetic as the `tallies` rule in
     * Firebase/firestore.rules, which refuses anything else. Values only, without the server time.
     */
    companion object {
        fun tally(old: LeaderboardEntry?, uid: String, username: String, day: String, correct: Boolean, timeMs: Int, points: Int): Map<String, Any?> {
            val lastWin = old?.lastWinDay ?: ""
            val oldStreak = old?.streak ?: 0
            val laterWin = correct && day > lastWin
            val previous = lastWin.isNotEmpty() && DailySchedule.shift(day, -1) == lastWin
            val streak = if (laterWin) (if (previous) oldStreak + 1 else 1) else (if (!correct && day > lastWin) 0 else oldStreak)
            val best: Int? = if (correct) minOf(old?.bestTimeMs ?: timeMs, timeMs) else old?.bestTimeMs
            return mapOf(
                "uid" to uid, "username" to username, "points" to (old?.points ?: 0) + points, "played" to (old?.played ?: 0) + 1,
                "wins" to (old?.wins ?: 0) + (if (correct) 1 else 0), "streak" to streak, "bestStreak" to maxOf(old?.bestStreak ?: 0, streak),
                "bestTimeMs" to best, "lastWinDay" to if (laterWin) day else lastWin, "lastResult" to day,
            )
        }
    }
}

/** Where a finished daily result stands among today's players. */
data class DailyStanding(val rank: Int?, val players: Int, val beatenPercent: Int?) {
    /** "Top X %" badge, rounded up to 1, 5, 10, 25 or 50 %. Null for number 1 and the slower half. */
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
    val points: Int,
    val streak: Int,
    val today: Attempt?,
    val todayWrong: Int? = null,
) {
    companion object {
        /** Found today first (fastest first), then the others by points. */
        fun ordered(rows: List<FriendStanding>): List<FriendStanding> = rows.sortedWith { a, b ->
            val fa = a.today?.correct == true
            val fb = b.today?.correct == true
            when {
                fa != fb -> if (fa) -1 else 1
                fa && a.today!!.timeMs != b.today!!.timeMs -> a.today.timeMs.compareTo(b.today.timeMs)
                a.points != b.points -> b.points.compareTo(a.points)
                else -> a.username.compareTo(b.username, ignoreCase = true)
            }
        }
    }
}
