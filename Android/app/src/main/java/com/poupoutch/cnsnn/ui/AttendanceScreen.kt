package com.poupoutch.cnsnn.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.poupoutch.cnsnn.core.DailySchedule
import com.poupoutch.cnsnn.core.Format
import com.poupoutch.cnsnn.data.CloudError
import com.poupoutch.cnsnn.data.DayUsage
import com.poupoutch.cnsnn.state.AppViewModel
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

private val modes = listOf("daily" to "Mot du jour", "classic" to "Classique", "sprint" to "Sprint", "survival" to "Survie", "duo" to "Double sens", "challenge" to "Défis")
private val dayLabel = DateTimeFormatter.ofPattern("EEE d MMM", Locale.FRANCE)

/** Admins only: the anonymous attendance of the last two weeks (`stats/{day}`, see core Usage.kt). */
@Composable
fun AttendanceContent(state: AppViewModel) {
    var days by remember { mutableStateOf<List<DayUsage>>(emptyList()) }
    var loaded by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    val today = DailySchedule.key()
    LaunchedEffect(Unit) {
        try {
            if (!state.cloud.isAdmin()) { message = "Accès administrateur requis."; return@LaunchedEffect }
            days = state.cloud.usage(DailySchedule.shift(today, -13)); loaded = true
        } catch (e: Exception) { message = CloudError.message(e) }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        message?.let { SectionCard { Text(it) } }
        if (loaded) {
            Summary("Aujourd’hui", days.firstOrNull { it.day == today }?.counts.orEmpty())
            val week = DailySchedule.shift(today, -6)
            Summary("7 derniers jours", days.filter { it.day >= week }.flatMap { it.counts.entries }.groupBy({ it.key }, { it.value }).mapValues { it.value.sum() })
        }
        Kicker("Par jour", modifier = Modifier.padding(top = 10.dp))
        if (days.isEmpty()) Text(if (loaded) "Aucun chiffre pour l’instant." else "Chargement…", color = Palette.secondary)
        if (days.isNotEmpty()) SectionCard(radius = 22.dp, padding = 16.dp) {
            days.forEach { day ->
                val games = modes.sumOf { day.counts[it.first] ?: 0 }
                val players = day.counts["players"] ?: 0
                Row(Modifier.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(runCatching { LocalDate.parse(day.day).format(dayLabel) }.getOrDefault(day.day), modifier = Modifier.weight(1f))
                    Text("$players joueur${if (players > 1) "s" else ""} · $games partie${if (games > 1) "s" else ""}", color = Palette.secondary, fontSize = 14.sp)
                }
            }
        }
        Text("Comptés par téléphone, sans nom ni identifiant : un joueur sur deux appareils compte deux fois. Les téléphones sans la dernière version de l’app ne sont pas comptés.",
            fontSize = 12.sp, color = Palette.tertiary)
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun Summary(title: String, c: Map<String, Int>) {
    val opens = (c["opensIos"] ?: 0) + (c["opensAndroid"] ?: 0)
    val new = (c["newIos"] ?: 0) + (c["newAndroid"] ?: 0)
    Kicker(title, modifier = Modifier.padding(top = 10.dp))
    SectionCard(radius = 22.dp, padding = 16.dp) {
        Line("Joueurs", c["players"] ?: 0, "dont ${c["newPlayers"] ?: 0} nouveaux")
        Line("Ouvertures de l’app", opens, "iPhone ${c["opensIos"] ?: 0} · Android ${c["opensAndroid"] ?: 0}")
        Line("Nouveaux appareils", new, "dont ${maxOf(0, new - (c["newPlayers"] ?: 0))} sans partie")
        Line("Parties", modes.sumOf { c[it.first] ?: 0 }, null)
        modes.forEach { (key, label) -> Line("   $label", c[key] ?: 0, null) }
    }
}

@Composable
private fun Line(title: String, value: Int, detail: String?) {
    Row(Modifier.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title)
            if (detail != null) Text(detail, fontSize = 12.sp, color = Palette.secondary)
        }
        Text(Format.number(value), fontWeight = FontWeight.SemiBold)
    }
}
