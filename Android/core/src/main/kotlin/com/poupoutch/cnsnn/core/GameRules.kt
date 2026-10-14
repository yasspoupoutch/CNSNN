package com.poupoutch.cnsnn.core

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

object Scoring {
    /** Same formula as Core/GameRules.swift and firestore.rules `dailyPoints`. */
    fun points(difficulty: Difficulty, timeMs: Int, usedHint: Boolean, correct: Boolean): Int {
        if (!correct) return 0
        val bonus = maxOf(0, 50 - maxOf(0, timeMs) / 1000)
        return (difficulty.basePoints + bonus) / (if (usedHint) 2 else 1)
    }
}

/** The Mot du jour calendar: one word per day, keyed yyyy-MM-dd in Europe/Paris. */
object DailySchedule {
    val zone: ZoneId = ZoneId.of("Europe/Paris")
    private val reference: LocalDate = LocalDate.of(2024, 1, 1)

    fun key(at: Instant = Instant.now()): String = at.atZone(zone).toLocalDate().toString()
    fun shift(key: String, days: Long): String = LocalDate.parse(key).plusDays(days).toString()
    /** Days since Monday 2024-01-01. */
    fun dayNumber(key: String): Int? = runCatching { ChronoUnit.DAYS.between(reference, LocalDate.parse(key)).toInt() }.getOrNull()
    /** Monday-Tuesday easy, Wednesday-Friday medium, weekend hard (same table as firestore.rules). */
    fun difficulty(key: String): Difficulty? = dayNumber(key)?.let {
        when (((it % 7) + 7) % 7) { 0, 1 -> Difficulty.EASY; 2, 3, 4 -> Difficulty.MEDIUM; else -> Difficulty.HARD }
    }
    /** The next Paris midnight, when the Mot du jour changes. */
    fun nextDay(at: Instant = Instant.now()): Instant =
        at.atZone(zone).toLocalDate().plusDays(1).atStartOfDay(zone).toInstant()
}

object CardPicker {
    /** Cards matching the filters, preferring those not seen recently. */
    fun candidates(cards: List<Card>, category: Category?, difficulty: Difficulty?, recent: List<String>): List<Card> {
        val eligible = cards.filter { it.status == ReviewStatus.APPROVED && (category == null || it.category == category) && (difficulty == null || it.difficulty == difficulty) }
        val fresh = eligible.filter { it.id !in recent }
        if (fresh.isNotEmpty()) return fresh
        return listOfNotNull(eligible.minByOrNull { recent.indexOf(it.id) })
    }
}

/** Secret daily words: the card id names the day ("secret-2026-10-14"). */
object SecretDaily {
    fun cardId(day: String) = "secret-$day"
    fun day(cardId: String): String? = if (cardId.startsWith("secret-")) cardId.removePrefix("secret-") else null
}

object Mistakes {
    /** "sans faute", "1 erreur", "3 erreurs": wrong guesses on the day's word. */
    fun text(count: Int): String = when {
        count <= 0 -> "sans faute"
        count == 1 -> "1 erreur"
        else -> "$count erreurs"
    }
}

object Format {
    fun clock(ms: Int): String { val total = maxOf(0, ms / 1000); return "${total / 60}:" + "%02d".format(total % 60) }
    /** French grouping with a narrow no-break space: 12 345. */
    fun number(value: Int): String = "%,d".format(java.util.Locale.US, value).replace(',', ' ')
    /** 1er, 2e, 3e… */
    fun ordinal(value: Int): String = if (value == 1) "1er" else "${number(value)}e"
    fun seconds(ms: Int?): String = ms?.let { String.format(java.util.Locale.FRENCH, "%.1f s", it / 1000.0) } ?: "—"
    fun countdown(seconds: Long): String { val s = maxOf(0, seconds); return "%02d:%02d:%02d".format(s / 3600, s % 3600 / 60, s % 60) }
}

/** Letters and digits that cannot be confused when read aloud or typed (no I, O, 0, 1). */
object FriendCode {
    const val ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    fun normalize(text: String): String = text.uppercase().filter { it in ALPHABET }.take(6)
    fun random(): String = (1..6).map { ALPHABET.random() }.joinToString("")
}
