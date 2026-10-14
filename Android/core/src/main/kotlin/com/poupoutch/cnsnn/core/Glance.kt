package com.poupoutch.cnsnn.core

import kotlinx.serialization.Serializable
import java.time.Instant

/** What the home screen widget and the reminders need: the last daily result and the streak. */
@Serializable
data class Glance(
    val lastDailyKey: String? = null,
    val lastDailyCorrect: Boolean = false,
    val lastDailyTimeMs: Int = 0,
    /** Streak of found daily words, counted up to the last win. */
    val streak: Int = 0,
    val lastWinKey: String? = null,
) {
    fun playedToday(at: Instant = Instant.now()): Boolean = lastDailyKey == DailySchedule.key(at)
    /** The streak still counts while the last win is today or yesterday. */
    fun currentStreak(at: Instant = Instant.now()): Int {
        val today = DailySchedule.key(at)
        return if (lastWinKey == today || lastWinKey == DailySchedule.shift(today, -1)) streak else 0
    }
    fun toJson(): String = ProgressJson.encodeToString(serializer(), this)

    companion object {
        fun of(progress: Progress, streak: Int): Glance {
            val last = progress.attempts.filter { it.mode == GameMode.DAILY && it.dailyKey != null }.maxByOrNull { it.dailyKey!! }
            val lastWin = progress.attempts.filter { it.mode == GameMode.DAILY && it.correct }.mapNotNull { it.dailyKey }.maxOrNull()
            return Glance(last?.dailyKey, last?.correct ?: false, last?.timeMs ?: 0, streak, lastWin)
        }
        fun fromJson(json: String?): Glance? = json?.let { runCatching { ProgressJson.decodeFromString(serializer(), it) }.getOrNull() }
    }
}
