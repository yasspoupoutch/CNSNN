package com.poupoutch.cnsnn.data

import android.content.Context
import com.poupoutch.cnsnn.core.Card
import com.poupoutch.cnsnn.core.DuoGame
import com.poupoutch.cnsnn.core.Glance
import com.poupoutch.cnsnn.core.PlayMode
import com.poupoutch.cnsnn.core.Progress
import com.poupoutch.cnsnn.core.ProgressJson
import com.poupoutch.cnsnn.core.SprintGame
import com.poupoutch.cnsnn.core.SurvivalGame
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import java.util.UUID

/**
 * Progress kept on the phone, one copy per account (like the iPhone's per-UID archives),
 * plus small settings. A file that cannot be read is never overwritten.
 */
class LocalStore(context: Context) {
    private val prefs = context.getSharedPreferences("cnsnn", Context.MODE_PRIVATE)

    private fun key(scope: String?) = if (scope == null) "progress" else "progress.$scope"
    /** Null when the saved copy is unreadable. */
    fun load(scope: String? = null): Progress? {
        val json = prefs.getString(key(scope), null) ?: return Progress()
        return runCatching { Progress.fromJson(json) }.getOrNull()
    }
    fun save(progress: Progress, scope: String? = null) { prefs.edit().putString(key(scope), progress.toJson()).apply() }
    fun erase(scope: String? = null) { prefs.edit().remove(key(scope)).apply() }

    /** The account whose archive is in use, so a relaunch opens the right copy before the network answers. */
    var activeScope: String?
        get() = prefs.getString("activeScope", null)
        set(value) { prefs.edit().putString("activeScope", value).apply() }

    var avatar: Int
        get() = prefs.getInt("avatar", 0)
        set(value) { prefs.edit().putInt("avatar", value).apply() }
    /** Players this phone chose to hide from the leaderboards. */
    var hiddenPlayers: Set<String>
        get() = prefs.getStringSet("hiddenPlayers", emptySet())!!.toSet()
        set(value) { prefs.edit().putStringSet("hiddenPlayers", value).apply() }

    var remindersEnabled: Boolean
        get() = prefs.getBoolean("reminders.enabled", false)
        set(value) { prefs.edit().putBoolean("reminders.enabled", value).apply() }
    /** Minutes after midnight, 9:00 by default. */
    var reminderMinutes: Int
        get() = prefs.getInt("reminders.minutes", 9 * 60)
        set(value) { prefs.edit().putInt("reminders.minutes", value).apply() }

    var glance: Glance?
        get() = Glance.fromJson(prefs.getString("glance", null))
        set(value) { prefs.edit().putString("glance", value?.toJson()).apply() }

    /**
     * Approved community cards kept on the phone with the catalogue version (`meta/cards`, in ms,
     * 0 when the server has none yet) and the download time, so they are fetched again only when they changed.
     */
    val cachedCards: List<Card>?
        get() = prefs.getString("cards", null)?.let { json -> runCatching { ProgressJson.decodeFromString(ListSerializer(Card.serializer()), json) }.getOrNull() }
    val cardsVersion: Long get() = prefs.getLong("cards.version", -1)
    val cardsFetchedAt: Long get() = prefs.getLong("cards.fetchedAt", 0)
    fun storeCards(cards: List<Card>, version: Long, fetchedAt: Long) {
        prefs.edit().putString("cards", ProgressJson.encodeToString(ListSerializer(Card.serializer()), cards))
            .putLong("cards.version", version).putLong("cards.fetchedAt", fetchedAt).apply()
    }

    // ---- Sprint, Survie and Double sens

    /** The game in progress of a mode, saved after every move (never synced: only finished games become records). */
    fun loadRun(mode: PlayMode): ModeRun? =
        prefs.getString("run.${mode.key}", null)?.let { json -> runCatching { ProgressJson.decodeFromString(ModeRun.serializer(), json) }.getOrNull() }
    fun saveRun(run: ModeRun) { prefs.edit().putString("run.${run.mode}", ProgressJson.encodeToString(ModeRun.serializer(), run)).apply() }
    fun clearRun(mode: PlayMode) { prefs.edit().remove("run.${mode.key}").apply() }
    fun clearRuns() { PlayMode.entries.forEach(::clearRun) }

    /** An unfinished friend challenge: "index,found,skips,errors", the play time and when it was saved. */
    fun loadChallengeRun(id: String): Triple<String, Long, Long>? {
        val game = prefs.getString("challenge.$id", null) ?: return null
        return Triple(game, prefs.getLong("challenge.$id.elapsed", 0), prefs.getLong("challenge.$id.savedAt", 0))
    }
    fun saveChallengeRun(id: String, game: String, elapsedMs: Long, savedAt: Long = System.currentTimeMillis()) {
        prefs.edit().putString("challenge.$id", game).putLong("challenge.$id.elapsed", elapsedMs).putLong("challenge.$id.savedAt", savedAt).apply()
    }
    fun clearChallengeRun(id: String) {
        prefs.edit().remove("challenge.$id").remove("challenge.$id.elapsed").remove("challenge.$id.savedAt").apply()
    }

    /** Cards (Sprint, Survie) or duos (Double sens) played lately, so a new game draws other ones. */
    fun recent(mode: PlayMode): List<String> =
        prefs.getString(recentKey(mode), null)?.let { json -> runCatching { ProgressJson.decodeFromString(ListSerializer(String.serializer()), json) }.getOrNull() } ?: emptyList()
    fun remember(ids: List<String>, mode: PlayMode) {
        val limit = if (mode == PlayMode.DUO) 20 else 150
        val list = (recent(mode).filter { it !in ids } + ids).takeLast(limit)
        prefs.edit().putString(recentKey(mode), ProgressJson.encodeToString(ListSerializer(String.serializer()), list)).apply()
    }
    private fun recentKey(mode: PlayMode) = "recent." + if (mode == PlayMode.DUO) "duo" else "cards"

    /** One id per installation: each device counts its own games, so merging never adds a game twice. */
    val deviceID: String
        get() = prefs.getString("deviceID", null) ?: UUID.randomUUID().toString().also { prefs.edit().putString("deviceID", it).apply() }
}

/** A Sprint, Survie or Double sens game in progress, with its game time and the wall clock when saved. */
@Serializable
data class ModeRun(
    val mode: String,
    val sprint: SprintGame? = null,
    val survival: SurvivalGame? = null,
    val duo: DuoGame? = null,
    val elapsedMs: Int,
    val savedAt: Long,
) {
    val finished: Boolean get() = sprint?.finished ?: survival?.finished ?: duo?.finished ?: true
    /** The game time once reopened: the Sprint and Double sens clocks never stop, time away included. */
    fun resumedElapsedMs(now: Long = System.currentTimeMillis()): Int = elapsedMs + maxOf(0L, now - savedAt).coerceAtMost(Int.MAX_VALUE.toLong() / 2).toInt()
}
