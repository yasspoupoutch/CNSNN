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
}

/** Letters and digits that cannot be confused when read aloud or typed (no I, O, 0, 1). */
object FriendCode {
    const val ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    fun normalize(text: String): String = text.uppercase().filter { it in ALPHABET }.take(6)
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
