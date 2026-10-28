package com.poupoutch.cnsnn.core

import kotlinx.serialization.Serializable

/**
 * Anonymous attendance (`stats/{day}`, read by the admins only): how many phones opened the app or
 * played that day, and the games of each mode. Nothing names the player or the phone: each phone
 * remembers here what it already counted and only ever sends increments (same as the iPhone's Usage.swift).
 */
@Serializable
data class UsageTally(
    /** Counts not sent yet, by day (yyyy-MM-dd on the phone's calendar) then field. */
    val pending: Map<String, Map<String, Int>> = emptyMap(),
    /** Last day this phone counted itself as opened, and as played. */
    val openedDay: String? = null,
    val playedDay: String? = null,
    /** This phone was counted (or already used the app before the counter existed) and has played once. */
    val known: Boolean = false,
    val played: Boolean = false,
) {
    /**
     * The app is on screen. `platform` is "Ios" or "Android". `returning`: games or a pseudo already on
     * this phone, so a player updating the app is not counted as a new download.
     */
    fun open(day: String, platform: String, returning: Boolean): UsageTally {
        var next = this
        if (!known) {
            next = if (returning) next.copy(known = true, played = true) else next.copy(known = true).add("new$platform", day)
        }
        if (next.openedDay == day) return next
        return next.copy(openedDay = day).add("opens$platform", day)
    }
    /** A game finished: `mode` is one of `PLAY_FIELDS` after the first two. */
    fun play(mode: String, day: String): UsageTally {
        if (mode !in PLAY_FIELDS.drop(2)) return this
        var next = this
        if (playedDay != day) {
            next = next.copy(playedDay = day).add("players", day)
            if (!played) next = next.copy(played = true).add("newPlayers", day)
        }
        return next.add(mode, day)
    }
    /**
     * The counts to send by day, and what stays pending. Days before `oldest` are dropped (the server
     * refuses them); without an account only the opening counts go, the rest waits for the sign-in.
     */
    fun take(oldest: String, signedIn: Boolean): Pair<Map<String, Map<String, Int>>, UsageTally> {
        val sent = mutableMapOf<String, Map<String, Int>>()
        val left = mutableMapOf<String, Map<String, Int>>()
        for ((day, counts) in pending) {
            if (day < oldest) continue
            val ready = counts.filterKeys { signedIn || it in OPEN_FIELDS }
            if (ready.isNotEmpty()) sent[day] = ready
            val rest = counts.filterKeys { it !in ready }
            if (rest.isNotEmpty()) left[day] = rest
        }
        return sent to copy(pending = left)
    }
    private fun add(field: String, day: String): UsageTally {
        val counts = pending[day].orEmpty()
        return copy(pending = pending + (day to counts + (field to (counts[field] ?: 0) + 1)))
    }
    fun toJson(): String = ProgressJson.encodeToString(serializer(), this)

    companion object {
        /** Counted without an account (a phone that has not chosen a pseudo yet). */
        val OPEN_FIELDS = listOf("opensIos", "opensAndroid", "newIos", "newAndroid")
        /** Counted once signed in (see Firebase/firestore.rules). */
        val PLAY_FIELDS = listOf("players", "newPlayers", "daily", "classic", "sprint", "survival", "duo", "challenge")
        fun fromJson(json: String?): UsageTally = json?.let { runCatching { ProgressJson.decodeFromString(serializer(), it) }.getOrNull() } ?: UsageTally()
    }
}
