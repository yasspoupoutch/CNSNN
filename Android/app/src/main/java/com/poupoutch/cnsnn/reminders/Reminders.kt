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
import com.poupoutch.cnsnn.data.LocalStore
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * Daily Mot du jour reminder, computed on the phone (no server). One alarm at a time: the next
 * morning reminder at the chosen time, or tonight's 20:00 warning when a streak is at stake.
 * Each alarm schedules the following one; a reboot or app update reschedules.
 */
object Reminders {
    private const val CHANNEL = "daily"
    /** 12:00, the time offered after the first found daily word. */
    const val DEFAULT_MINUTES = 12 * 60

    fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val channel = NotificationChannel(CHANNEL, "Mot du jour", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "Le rappel quotidien du mot du jour et de votre série."
        }
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private data class Next(val at: ZonedDateTime, val evening: Boolean)

    private fun next(store: LocalStore, now: ZonedDateTime): Next? {
        if (!store.remindersEnabled) return null
        val glance = store.glance
        val played = glance?.playedToday(now.toInstant()) ?: false
        val streak = glance?.currentStreak(now.toInstant()) ?: 0
        val minutes = store.reminderMinutes
        val morning = { day: LocalDate -> ZonedDateTime.of(day, LocalTime.of(minutes / 60, minutes % 60), now.zone) }
        val today = now.toLocalDate()
        val candidates = buildList {
            if (!played) add(Next(morning(today), false))
            if (!played && streak > 0) add(Next(ZonedDateTime.of(today, LocalTime.of(20, 0), now.zone), true))
            add(Next(morning(today.plusDays(1)), false))
        }
        return candidates.filter { it.at.isAfter(now) }.minByOrNull { it.at }
    }

    fun schedule(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        val pending = PendingIntent.getBroadcast(context, 0, Intent(context, ReminderReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        alarms.cancel(pending)
        val next = next(LocalStore(context), ZonedDateTime.now(ZoneId.systemDefault())) ?: return
        // Inexact but battery friendly: a few minutes late at most, no special permission needed.
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.at.toInstant().toEpochMilli(), pending)
    }

    internal fun fire(context: Context) {
        val store = LocalStore(context)
        val now = Instant.now()
        val glance = store.glance
        if (store.remindersEnabled && glance?.playedToday(now) != true) {
            val streak = glance?.currentStreak(now) ?: 0
            val evening = ZonedDateTime.now().hour >= 20
            val title = if (evening) "Votre série est en jeu" else "N’oubliez pas le mot du jour"
            val body = when {
                evening -> "$streak jour${if (streak > 1) "s" else ""} d’affilée : le mot du jour s’arrête à minuit."
                streak > 0 -> "Gardez votre série de $streak jour${if (streak > 1) "s" else ""} : trouvez le mot avant ce soir."
                else -> "Nouveau mot, nouveau classement. Serez-vous le numéro 1 aujourd’hui ?"
            }
            val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
                PendingIntent.FLAG_IMMUTABLE)
            val notification = NotificationCompat.Builder(context, CHANNEL).setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(title).setContentText(body).setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setContentIntent(open).setAutoCancel(true).build()
            val allowed = android.os.Build.VERSION.SDK_INT < 33 || androidx.core.content.ContextCompat.checkSelfPermission(context,
                android.Manifest.permission.POST_NOTIFICATIONS) == android.content.pm.PackageManager.PERMISSION_GRANTED
            if (allowed) runCatching { NotificationManagerCompat.from(context).notify(1, notification) }
        }
        schedule(context)
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) = Reminders.fire(context)
}

/** Alarms do not survive a reboot or an update of the app: set the next one again. */
class RescheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Reminders.schedule(context)
        com.poupoutch.cnsnn.widget.DailyWidget.refresh(context)
    }
}
