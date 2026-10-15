package com.poupoutch.cnsnn.reminders

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.poupoutch.cnsnn.MainActivity
import com.poupoutch.cnsnn.R
import com.poupoutch.cnsnn.core.Challenge
import com.poupoutch.cnsnn.core.ChallengeAlerts
import com.poupoutch.cnsnn.data.CloudRepository
import com.poupoutch.cnsnn.data.LocalStore
import java.util.concurrent.TimeUnit

/**
 * Friend challenge notifications without a server. About every 15 minutes, when the system allows it
 * (network on, battery not low, batched with other apps), a worker reads the challenges of the last
 * two days (a few documents) and shows a notification for a new challenge or a result.
 */
object ChallengeWatch {
    private const val CHANNEL = "challenges"
    private const val WORK = "challenge-watch"

    fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val channel = NotificationChannel(CHANNEL, "Défis entre amis", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "Quand un ami vous défie, et le résultat de vos défis."
        }
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    /** Background checks only while someone can challenge this player. */
    fun setActive(context: Context, active: Boolean) {
        LocalStore(context).challengeWatch = active
        val work = WorkManager.getInstance(context)
        if (!active) { work.cancelUniqueWork(WORK); return }
        val constraints = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).setRequiresBatteryNotLow(true).build()
        val request = PeriodicWorkRequestBuilder<ChallengeWorker>(15, TimeUnit.MINUTES).setConstraints(constraints).build()
        work.enqueueUniquePeriodicWork(WORK, ExistingPeriodicWorkPolicy.KEEP, request)
    }

    /** One check: returns the notifications it showed (or would show, without the permission). */
    suspend fun check(context: Context, cloud: CloudRepository = CloudRepository(), now: Long = System.currentTimeMillis()): List<ChallengeAlerts.Alert> {
        val store = LocalStore(context)
        if (!store.challengeWatch) return emptyList()
        val uid = cloud.currentUid ?: return emptyList()
        val alerts = ChallengeAlerts.pending(cloud.recentChallenges(uid, now), uid, now, store.seenChallengeAlerts)
        store.rememberChallengeAlerts(alerts.map { it.key })
        alerts.forEach { show(context, it) }
        return alerts
    }

    /** What the app already showed on screen needs no notification later. */
    fun markSeen(context: Context, challenges: List<Challenge>, uid: String, now: Long = System.currentTimeMillis()) =
        LocalStore(context).rememberChallengeAlerts(ChallengeAlerts.all(challenges, uid, now).map { it.key })

    private fun show(context: Context, alert: ChallengeAlerts.Alert) {
        val allowed = Build.VERSION.SDK_INT < 33 || androidx.core.content.ContextCompat.checkSelfPermission(context,
            android.Manifest.permission.POST_NOTIFICATIONS) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (!allowed) return
        val open = PendingIntent.getActivity(context, 1, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(context, CHANNEL).setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(alert.title).setContentText(alert.body).setStyle(NotificationCompat.BigTextStyle().bigText(alert.body))
            .setContentIntent(open).setAutoCancel(true).build()
        runCatching { NotificationManagerCompat.from(context).notify(alert.key.hashCode(), notification) }
    }
}

class ChallengeWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    // A failed check (offline, signed out) simply waits for the next one: no retries, no extra wake-ups.
    override suspend fun doWork(): Result {
        runCatching { ChallengeWatch.check(applicationContext) }
        return Result.success()
    }
}
