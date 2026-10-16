package com.poupoutch.cnsnn.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.poupoutch.cnsnn.core.Card
import com.poupoutch.cnsnn.core.Category
import com.poupoutch.cnsnn.core.DailySchedule
import com.poupoutch.cnsnn.core.Difficulty
import com.poupoutch.cnsnn.core.Format
import com.poupoutch.cnsnn.data.CardReport
import com.poupoutch.cnsnn.data.CloudError
import com.poupoutch.cnsnn.data.DailyRank
import com.poupoutch.cnsnn.data.PlayerReport
import com.poupoutch.cnsnn.data.SuspendedPlayer
import com.poupoutch.cnsnn.state.AppViewModel
import kotlinx.coroutines.launch

/** Moderator tools. The rules check the admin role on every write; hiding this screen is only comfort. */
@Composable
fun ModerationContent(state: AppViewModel) {
    var cards by remember { mutableStateOf<List<Card>>(emptyList()) }
    var reports by remember { mutableStateOf<List<CardReport>>(emptyList()) }
    var playerReports by remember { mutableStateOf<List<PlayerReport>>(emptyList()) }
    var suspended by remember { mutableStateOf<List<SuspendedPlayer>>(emptyList()) }
    var suspicious by remember { mutableStateOf<List<DailyRank>>(emptyList()) }
    var busy by remember { mutableStateOf(false) }
    var loaded by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    val cloud = state.cloud
    suspend fun refresh() {
        try {
            if (!cloud.isAdmin()) { message = "Accès administrateur requis."; return }
            cards = cloud.pendingCards(); reports = cloud.pendingReports()
            playerReports = cloud.pendingPlayerReports(); suspended = cloud.suspendedPlayers()
            suspicious = cloud.suspiciousTimes(DailySchedule.key())
            loaded = true
        } catch (e: Exception) { message = CloudError.message(e) }
    }
    fun act(work: suspend () -> Unit) {
        if (busy) return
        busy = true; message = null
        scope.launch {
            try { work(); haptics.success(); refresh(); state.refreshCards() } catch (e: Exception) { message = CloudError.message(e) } finally { busy = false }
        }
    }
    LaunchedEffect(Unit) { refresh() }
    val loading = if (loaded) null else "Chargement…"

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        message?.let { SectionCard { Text(it) } }
        Kicker("Cartes en attente")
        if (cards.isEmpty()) Text(loading ?: "Aucune carte à examiner.", color = Palette.secondary)
        cards.forEach { original ->
            var card by remember(original.id) { mutableStateOf(original) }
            SectionCard(radius = 22.dp, padding = 16.dp) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(card.wordFull, fontWeight = FontWeight.Bold, fontSize = 17.sp, modifier = Modifier.weight(1f))
                    Text(card.wordNoVowels, fontFamily = FontFamily.Monospace, color = Palette.secondary)
                }
                Text("Proposée par " + (card.author ?: "un joueur inconnu"), fontSize = 13.sp, color = Palette.secondary)
                OutlinedTextField(card.hint, { card = card.copy(hint = it.take(160)) }, Modifier.fillMaxWidth().padding(top = 8.dp), label = { Text("Indice") }, maxLines = 3)
                Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    ChipRow(Category.entries, card.category, { it.label }) { card = card.copy(category = it) }
                    ChipRow(Difficulty.entries, card.difficulty, { it.label }) { card = card.copy(difficulty = it) }
                }
                Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button({ act { cloud.review(card.copy(hint = card.hint.trim()), true) } }, enabled = !busy && card.hint.trim().length in 5..160) { Text("Approuver") }
                    OutlinedButton({ act { cloud.review(card, false) } }, enabled = !busy) { Text("Refuser", color = Palette.red) }
                }
            }
        }
        Text("Vous pouvez corriger l’indice, la catégorie et la difficulté avant d’approuver. Le mot ne change pas.", fontSize = 12.sp, color = Palette.tertiary)

        Kicker("Cartes signalées", modifier = Modifier.padding(top = 10.dp))
        if (reports.isEmpty()) Text(loading ?: "Aucun signalement en attente.", color = Palette.secondary)
        reports.forEach { report ->
            SectionCard(radius = 22.dp, padding = 16.dp) {
                Text(report.word ?: report.cardId, fontWeight = FontWeight.Bold)
                Text(report.reason, modifier = Modifier.padding(top = 4.dp))
                Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton({ act { cloud.withdraw(report) } }, enabled = !busy) { Text("Retirer la carte", color = Palette.red) }
                    OutlinedButton({ act { cloud.resolve(report) } }, enabled = !busy) { Text("Garder la carte") }
                }
            }
        }

        Kicker("Pseudos signalés", modifier = Modifier.padding(top = 10.dp))
        if (playerReports.isEmpty()) Text(loading ?: "Aucun pseudo signalé.", color = Palette.secondary)
        playerReports.forEach { report ->
            SectionCard(radius = 22.dp, padding = 16.dp) {
                Text(report.username, fontWeight = FontWeight.Bold)
                Text(report.reason, color = Palette.secondary)
                Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button({ act { cloud.suspend(report.playerId, report.username, report.reason); cloud.resolve(report) } }, enabled = !busy,
                        colors = ButtonDefaults.buttonColors(containerColor = Palette.red)) { Text("Suspendre") }
                    OutlinedButton({ act { cloud.resolve(report) } }, enabled = !busy) { Text("Ignorer") }
                }
            }
        }
        Text("Un joueur suspendu disparaît des classements et ne peut plus jouer le mot du jour classé, proposer ni signaler. Ses résultats et ses stats sont conservés.", fontSize = 12.sp, color = Palette.tertiary)

        Kicker("Temps suspects", modifier = Modifier.padding(top = 10.dp))
        if (suspicious.isEmpty()) Text(loading ?: "Aucun temps sous 5 secondes aujourd’hui.", color = Palette.secondary)
        suspicious.forEach { rank ->
            SectionCard(radius = 22.dp, padding = 16.dp) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(rank.username, fontWeight = FontWeight.SemiBold)
                        Text(Format.seconds(rank.timeMs) + if (rank.usedHint) " · indice" else "", fontSize = 12.sp, color = Palette.secondary)
                    }
                    Button({ act { cloud.suspend(rank.uid, rank.username, "Temps suspect") } }, enabled = !busy,
                        colors = ButtonDefaults.buttonColors(containerColor = Palette.red)) { Text("Suspendre") }
                }
            }
        }
        Text("Mots du jour trouvés aujourd’hui en moins de 5 secondes.", fontSize = 12.sp, color = Palette.tertiary)

        Kicker("Joueurs suspendus", modifier = Modifier.padding(top = 10.dp))
        if (suspended.isEmpty()) Text(loading ?: "Aucun joueur suspendu.", color = Palette.secondary)
        suspended.forEach { player ->
            SectionCard(radius = 22.dp, padding = 16.dp) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(player.username, fontWeight = FontWeight.SemiBold)
                        if (player.reason.isNotEmpty()) Text(player.reason, fontSize = 12.sp, color = Palette.secondary)
                    }
                    OutlinedButton({ act { cloud.unsuspend(player.id); message = "${player.username} est rétabli et retrouve ses résultats, ses stats et sa place au classement." } },
                        enabled = !busy) { Text("Rétablir") }
                }
            }
        }
        Text("Rétablir un joueur lui rend tout : ses résultats, ses stats et sa place au classement.", fontSize = 12.sp, color = Palette.tertiary)
        Spacer(Modifier.height(24.dp))
    }
}
