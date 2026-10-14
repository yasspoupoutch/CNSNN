package com.poupoutch.cnsnn.data

import android.content.Context
import com.poupoutch.cnsnn.core.Glance
import com.poupoutch.cnsnn.core.Progress

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
}
