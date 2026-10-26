package com.poupoutch.cnsnn.core

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/**
 * The Mot du jour is scored on time only, the lower the better: the hint adds one minute, and a lost
 * (or unplayed) day counts ten minutes, the most a day can cost. Same arithmetic as firestore.rules
 * (`dailyScore`, `dailyRank`, `monthIndex`, `tallyMonth`) and Core/GameRules.swift.
 */
object DailyScore {
    const val HINT_PENALTY_MS = 60_000
    const val MISSED_MS = 600_000
    /** Days from 1970-01-01 to 2024-01-01, where DailySchedule.dayNumber starts. */
    const val EPOCH_OFFSET = 19_723
    /** Spread of one day in `rank` and of one month in `monthRank`. */
    const val DAY_SPAN = 1_000_000L
    const val MONTH_SPAN = 100_000_000L
    /** A lost day sorts after every found one. */
    const val LOST_RANK = 999_999

    fun scoreMs(timeMs: Int, usedHint: Boolean, correct: Boolean): Int =
        if (correct) minOf(timeMs + (if (usedHint) HINT_PENALTY_MS else 0), MISSED_MS) else MISSED_MS
    /** Rattrapage: a missed day played later counts in the week with 5 minutes more (firestore.rules `catchUpScore`). */
    const val CATCH_UP_PENALTY_MS = 300_000
    fun catchUpScoreMs(timeMs: Int, usedHint: Boolean, correct: Boolean): Int =
        if (correct) minOf(scoreMs(timeMs, usedHint, true) + CATCH_UP_PENALTY_MS, MISSED_MS) else MISSED_MS
    /** Days since 1970 for a yyyy-MM-dd key, as the rules' `dayIndex`. */
    fun dayIndex(day: String): Long? = DailySchedule.dayNumber(day)?.let { it.toLong() + EPOCH_OFFSET }
    /** The first rank of a day: every result of that day sorts between base and base + 999 999. */
    fun dayBase(day: String): Long? = dayIndex(day)?.let { it * DAY_SPAN }
    /** One number per result that sorts the day's results: the day first, then the score (lost last). */
    fun rank(day: String, scoreMs: Int, correct: Boolean): Long? = dayBase(day)?.let { it + if (correct) scoreMs else LOST_RANK }
    /** year * 12 + month - 1. */
    fun monthIndex(day: String): Int? {
        val parts = day.split("-").mapNotNull { it.toIntOrNull() }
        return if (parts.size == 3) parts[0] * 12 + parts[1] - 1 else null
    }
    fun monthRank(month: Int, saved: Int): Long = month * MONTH_SPAN + saved
    /** The month's total time after `dayOfMonth` days: every day costs ten minutes minus what was saved. */
    fun monthTotal(saved: Int, dayOfMonth: Int): Int = maxOf(0, MISSED_MS * dayOfMonth - saved)
    fun dayOfMonth(day: String): Int = day.split("-").lastOrNull()?.toIntOrNull() ?: 1

    /** One player's month: its index, the time saved against ten minutes a day, and the days played. */
    data class Month(val month: Int = 0, val saved: Int = 0, val played: Int = 0) {
        val rank: Long get() = DailyScore.monthRank(month, saved)
    }
    /**
     * The month after one more result: a new month starts from zero, and a late result from an older
     * month (finished after midnight) leaves the current one alone, as the rules' `tallyMonth`.
     */
    fun tally(old: Month, day: String, scoreMs: Int): Month {
        val month = monthIndex(day) ?: return old
        if (month < old.month) return old
        val same = month == old.month
        return Month(month, (if (same) old.saved else 0) + MISSED_MS - scoreMs, (if (same) old.played else 0) + 1)
    }
}

/** Classique has no points: the level grows with the words found, 20 per level. */
object ClassicLevel {
    const val WORDS_PER_LEVEL = 20
    fun level(words: Int): Int = words / WORDS_PER_LEVEL + 1
    fun into(words: Int): Int = words % WORDS_PER_LEVEL
}

/**
 * The Mot du jour calendar: one word per day, keyed yyyy-MM-dd on the phone's own time zone, so the
 * word changes at the player's local midnight (firestore.rules accepts a day while it is that day
 * somewhere on Earth).
 */
object DailySchedule {
    val zone: ZoneId get() = ZoneId.systemDefault()
    private val reference: LocalDate = LocalDate.of(2024, 1, 1)

    fun key(at: Instant = Instant.now(), zone: ZoneId = this.zone): String = at.atZone(zone).toLocalDate().toString()
    fun shift(key: String, days: Long): String = LocalDate.parse(key).plusDays(days).toString()
    /** Days since Monday 2024-01-01. */
    fun dayNumber(key: String): Int? = runCatching { ChronoUnit.DAYS.between(reference, LocalDate.parse(key)).toInt() }.getOrNull()
    /** Monday-Tuesday easy, Wednesday-Friday medium, weekend hard (same table as firestore.rules). */
    fun difficulty(key: String): Difficulty? = dayNumber(key)?.let {
        when (((it % 7) + 7) % 7) { 0, 1 -> Difficulty.EASY; 2, 3, 4 -> Difficulty.MEDIUM; else -> Difficulty.HARD }
    }
    /** The next local midnight, when the Mot du jour changes. */
    fun nextDay(at: Instant = Instant.now(), zone: ZoneId = this.zone): Instant =
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
    /** 1:05, then 1:02:05 past an hour (a daily word opened the night before and found the next evening). */
    fun clock(ms: Int): String {
        val total = maxOf(0, ms / 1000)
        if (total >= 3600) return "${total / 3600}:" + "%02d:%02d".format(total % 3600 / 60, total % 60)
        return "${total / 60}:" + "%02d".format(total % 60)
    }
    /** French grouping with a narrow no-break space: 12 345. */
    fun number(value: Int): String = "%,d".format(java.util.Locale.US, value).replace(',', ' ')
    /** 1er, 2e, 3e… */
    fun ordinal(value: Int): String = if (value == 1) "1er" else "${number(value)}e"
    fun seconds(ms: Int?): String = ms?.let { String.format(java.util.Locale.FRENCH, "%.1f s", it / 1000.0) } ?: "—"
    fun countdown(seconds: Long): String { val s = maxOf(0, seconds); return "%02d:%02d:%02d".format(s / 3600, s % 3600 / 60, s % 60) }
    /** "mardi" for a yyyy-MM-dd key. */
    fun weekday(key: String): String = runCatching {
        LocalDate.parse(key).dayOfWeek.getDisplayName(java.time.format.TextStyle.FULL, java.util.Locale.FRENCH)
    }.getOrDefault(key)
    /** "Mardi 21 octobre" for a yyyy-MM-dd key. */
    fun day(key: String): String = runCatching {
        LocalDate.parse(key).format(java.time.format.DateTimeFormatter.ofPattern("EEEE d MMMM", java.util.Locale.FRENCH)).replaceFirstChar { it.uppercase() }
    }.getOrDefault(key)
}

/** Letters and digits that cannot be confused when read aloud or typed (no I, O, 0, 1). */
object FriendCode {
    /** Letters and digits that cannot be confused when read aloud or typed (no I, O, 0, 1): the drawn codes. */
    const val ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    /** A code the player chooses ("YASIN10") may use any letter or digit, 4 to 12 of them. */
    val LENGTH = 4..12
    fun normalize(text: String): String = text.uppercase().filter { it in 'A'..'Z' || it in '0'..'9' }.take(LENGTH.last)
    fun random(): String = (1..6).map { ALPHABET.random() }.joinToString("")
}

/** The public site: rules, privacy policy, and the link that ends every share. */
object Site {
    const val URL = "https://cnsnn-9ctosy.web.app"
    const val RULES = "$URL/regles"
    const val PRIVACY = "$URL/confidentialite"
    fun friendInvite(code: String) = "Ajoute-moi sur CNSNN pour comparer nos temps au mot du jour : mon code ami est $code. $URL"
}

/** The community rules every player accepts (same text and version as the iPhone app and the site). */
object CommunityRules {
    const val VERSION = 1
    const val TITLE = "Règles de la communauté"
    val items = listOf(
        "Un pseudo correct : pas d’insulte, de propos haineux ou sexuels, ni d’usurpation d’identité.",
        "Des cartes pour tous : les mots et indices proposés ne contiennent rien d’offensant ni de données personnelles.",
        "Pas de triche : ni programme, ni aide automatique, ni comptes multiples pour fausser les classements.",
        "Du respect : pas de harcèlement, pas de signalements abusifs.",
        "La modération peut refuser une carte, masquer un pseudo ou suspendre un compte. Une question : jeucnsnn@gmail.com.",
    )
    /** A player with a pseudo who has not accepted the current version yet. */
    fun mustAccept(progress: Progress): Boolean = progress.username.isNotEmpty() && (progress.rulesVersion ?: 0) < VERSION
}

/** The Mot du jour allows 20 guesses, each counted by the server before it is checked. */
object Guesses {
    const val MAX = 20
    /** "Plus que 3 essais" once 5 or fewer remain, null before. */
    fun remainingText(used: Int): String? {
        val left = MAX - used
        return when {
            left > 5 || left < 1 -> null
            left == 1 -> "Plus qu’un essai"
            else -> "Plus que $left essais"
        }
    }
}

/**
 * Rattrapage: the daily words of the week (Monday to yesterday) a player missed can be played later.
 * They count in the week's ranking with 5 minutes more, and stay out of the day's ranking. A day opens
 * at the player's own midnight (firestore.rules `catchUpOpen` accepts it once the day is over somewhere).
 * Same rule as CatchUp in Core/GameRules.swift.
 */
object CatchUp {
    sealed interface Status {
        /** Played, on the day or caught up: found or not. */
        data class Played(val found: Boolean) : Status
        /** Missed, can be caught up now. */
        data object Open : Status
        /** Missed, not over on this phone yet: opens at that time. */
        data class Later(val at: Instant) : Status
        /** Today, not played yet. */
        data object Today : Status
        /** Later this week. */
        data object Coming : Status
    }
    data class Day(val key: String, val status: Status)

    /** The midnight that ends the day in `zone`. */
    fun opensAt(day: String, zone: ZoneId = ZoneId.systemDefault()): Instant? = runCatching { LocalDate.parse(day).plusDays(1).atStartOfDay(zone).toInstant() }.getOrNull()

    /** Monday to Sunday of today's week. `results`: day to found. */
    fun week(today: String, results: Map<String, Boolean>, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): List<Day> {
        val date = runCatching { LocalDate.parse(today) }.getOrNull() ?: return emptyList()
        val monday = date.minusDays(date.dayOfWeek.value - 1L)
        return (0L until 7L).map { offset ->
            val day = monday.plusDays(offset)
            val key = day.toString()
            val opens = opensAt(key, zone)
            val found = results[key]
            Day(key, when {
                found != null -> Status.Played(found)
                day.isAfter(date) -> Status.Coming
                day == date -> Status.Today
                opens != null && opens.isAfter(now) -> Status.Later(opens)
                else -> Status.Open
            })
        }
    }
    /** The days of today's week before today, Monday first (none on Monday). */
    fun days(today: String, results: Map<String, Boolean>, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): List<Day> {
        val date = runCatching { LocalDate.parse(today) }.getOrNull() ?: return emptyList()
        return week(today, results, now, zone).take(date.dayOfWeek.value - 1)
    }
    /** Missed days still to play, open now or later today. */
    fun toPlay(days: List<Day>): Int = days.count { it.status == Status.Open || it.status is Status.Later }
}
