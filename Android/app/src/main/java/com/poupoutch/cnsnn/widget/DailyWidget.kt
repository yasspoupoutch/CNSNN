package com.poupoutch.cnsnn.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.poupoutch.cnsnn.MainActivity
import com.poupoutch.cnsnn.R
import com.poupoutch.cnsnn.core.DailySchedule
import com.poupoutch.cnsnn.core.Format
import com.poupoutch.cnsnn.data.LocalStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.time.Instant

/** Home screen widget: today's Mot du jour (to play, found or missed) and the daily streak. */
class DailyWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(DpSize(120.dp, 120.dp), DpSize(250.dp, 120.dp)))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val glance = LocalStore(context).glance
        provideContent { GlanceTheme { Content(glance) } }
    }

    @Composable
    private fun Content(glance: com.poupoutch.cnsnn.core.Glance?) {
        val now = Instant.now()
        val played = glance?.playedToday(now) ?: false
        val found = played && glance?.lastDailyCorrect == true
        val streak = glance?.currentStreak(now) ?: 0
        val wide = LocalSize.current.width >= 250.dp
        val gold = ColorProvider(Color(0xFFFFC65A)); val mint = ColorProvider(Color(0xFF5AE6C6))
        val white = ColorProvider(Color(0xFFF4F5F8)); val grey = ColorProvider(Color(0xB8F4F5F8))
        val status = if (!played) "À jouer" else if (found) "Trouvé" else "Raté"
        val detail = when {
            found -> "En " + Format.clock(glance!!.lastDailyTimeMs)
            played -> "Revenez demain"
            else -> DailySchedule.difficulty(DailySchedule.key(now))?.let { "Difficulté : " + it.label.lowercase() } ?: "Un nouveau mot vous attend"
        }
        Row(GlanceModifier.fillMaxSize().cornerRadius(24.dp).background(ImageProvider(R.drawable.widget_background))
            .clickable(actionStartActivity<MainActivity>()).padding(16.dp)) {
            Column(GlanceModifier.defaultWeight()) {
                Text("MOT DU JOUR", style = TextStyle(color = grey, fontSize = 11.sp, fontWeight = FontWeight.Bold))
                Spacer(GlanceModifier.height(4.dp))
                Text(status, style = TextStyle(color = if (!played) gold else if (found) mint else grey, fontSize = if (wide) 26.sp else 22.sp, fontWeight = FontWeight.Bold))
                Text(detail, style = TextStyle(color = grey, fontSize = 12.sp), maxLines = 2)
                Spacer(GlanceModifier.defaultWeight())
                Text("🔥 $streak jour${if (streak > 1) "s" else ""}", style = TextStyle(color = white, fontSize = 14.sp, fontWeight = FontWeight.Medium))
            }
            if (wide) {
                Spacer(GlanceModifier.width(12.dp))
                Column(horizontalAlignment = Alignment.End) {
                    Text("Prochain mot", style = TextStyle(color = grey, fontSize = 11.sp, fontWeight = FontWeight.Medium))
                    val hours = java.time.Duration.between(now, DailySchedule.nextDay(now)).toMinutes()
                    Text(if (hours >= 60) "dans ${hours / 60} h" else "dans $hours min", style = TextStyle(color = white, fontSize = 17.sp, fontWeight = FontWeight.Bold))
                }
            }
        }
    }

    companion object {
        private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        fun refresh(context: Context) { val app = context.applicationContext; scope.launch { runCatching { DailyWidget().updateAll(app) } } }
    }
}

class DailyWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DailyWidget()
}
