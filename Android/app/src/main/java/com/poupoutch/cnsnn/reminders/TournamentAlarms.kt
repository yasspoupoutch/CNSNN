package com.poupoutch.cnsnn.reminders

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.poupoutch.cnsnn.MainActivity
import com.poupoutch.cnsnn.R
import com.poupoutch.cnsnn.core.TournamentReminders
import com.poupoutch.cnsnn.state.TournamentStore
import com.poupoutch.cnsnn.ui.TournamentText

/**
 * The tournament's notifications on this phone ([TournamentReminders], same as the iPhone): the start,
 * each round while I am in, an evening reminder when my match is not played yet. Set again whenever the
 * tournament is read; kept on the phone so a reboot sets them again (RescheduleReceiver).
 */
object TournamentAlarms {
    private const val CHANNEL = "tournament"
    private const val KEY = "tournament.alarms"
    private const val MAX = 8
    private const val FIRST_CODE = 200

    fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val channel = NotificationChannel(CHANNEL, "Tournoi", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "Le début du tournoi, chaque tour où vous êtes qualifié, et un rappel quand votre match n’est pas joué."
        }
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun prefs(context: Context) = context.getSharedPreferences("tournament-alarms", Context.MODE_PRIVATE)

    fun update(context: Context, store: TournamentStore) {
        val alerts = TournamentReminders.plan(store.nextWeek, store.nextMine, if (store.currentLoaded) store.bracket() else null,
            store.uid, store.runs, store.nowMs) { TournamentText.day(it) }.take(MAX)
        val text = alerts.joinToString("\u0002") { listOf(it.id, it.atMs.toString(), it.title, it.body).joinToString("\u0001") }
        if (prefs(context).getString(KEY, null) == text) return
        prefs(context).edit().putString(KEY, text).apply()
        schedule(context)
    }

    private fun saved(context: Context): List<TournamentReminders.Alert> =
        prefs(context).getString(KEY, null).orEmpty().split("\u0002").mapNotNull { line ->
            val parts = line.split("\u0001")
            if (parts.size == 4) parts[1].toLongOrNull()?.let { TournamentReminders.Alert(parts[0], it, parts[2], parts[3]) } else null
        }

    private fun pending(context: Context, index: Int, alert: TournamentReminders.Alert?): PendingIntent {
        val intent = Intent(context, TournamentReceiver::class.java)
        alert?.let { intent.putExtra("title", it.title).putExtra("body", it.body).putExtra("index", index) }
        return PendingIntent.getBroadcast(context, FIRST_CODE + index, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun schedule(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        for (index in 0 until MAX) alarms.cancel(pending(context, index, null))
        val now = System.currentTimeMillis()
        saved(context).forEachIndexed { index, alert ->
            // Inexact but battery friendly: a few minutes late at most, no special permission needed.
            if (alert.atMs > now) alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, alert.atMs, pending(context, index, alert))
        }
    }

    internal fun fire(context: Context, intent: Intent) {
        val title = intent.getStringExtra("title") ?: return
        val body = intent.getStringExtra("body") ?: ""
        val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(context, CHANNEL).setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title).setContentText(body).setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(open).setAutoCancel(true).build()
        val allowed = Build.VERSION.SDK_INT < 33 || androidx.core.content.ContextCompat.checkSelfPermission(context,
            android.Manifest.permission.POST_NOTIFICATIONS) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (allowed) runCatching { NotificationManagerCompat.from(context).notify(300 + intent.getIntExtra("index", 0), notification) }
    }
}

class TournamentReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) = TournamentAlarms.fire(context, intent)
}
