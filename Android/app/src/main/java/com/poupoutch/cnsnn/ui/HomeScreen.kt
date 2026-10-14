package com.poupoutch.cnsnn.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.filled.AllInclusive
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.ViewAgenda
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import com.poupoutch.cnsnn.core.ModeStat
import com.poupoutch.cnsnn.core.PlayMode
import com.poupoutch.cnsnn.core.records
import kotlinx.coroutines.launch
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudDone
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.poupoutch.cnsnn.core.Category
import com.poupoutch.cnsnn.core.DailySchedule
import com.poupoutch.cnsnn.core.Difficulty
import com.poupoutch.cnsnn.core.Format
import com.poupoutch.cnsnn.core.GameMode
import com.poupoutch.cnsnn.share.Share
import com.poupoutch.cnsnn.state.AppViewModel
import kotlinx.coroutines.delay
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(state: AppViewModel, play: (GameMode, Category?, Difficulty?) -> Unit, playMode: (PlayMode) -> Unit) {
    var classic by rememberSaveable { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).statusBarsPadding().padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Header(state)
        DailyCard(state) { play(GameMode.DAILY, null, null) }
        Modes(state, openClassic = { classic = true }, playMode = playMode)
        Row(Modifier.fillMaxWidth().padding(bottom = 16.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
            Icon(if (state.uid == null) Icons.Filled.CloudOff else Icons.Filled.CloudDone, null, Modifier.size(16.dp), tint = Palette.tertiary)
            Text(syncLabel(state), style = MaterialTheme.typography.bodySmall, color = Palette.tertiary, modifier = Modifier.padding(start = 6.dp))
        }
    }
    if (classic) {
        val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        val scope = rememberCoroutineScope()
        ModalBottomSheet({ classic = false }, sheetState = sheet, containerColor = Palette.surfaceHigh) {
            ClassicCard(state) { c, d ->
                scope.launch { sheet.hide() }.invokeOnCompletion { classic = false; play(GameMode.CLASSIC, c, d) }
            }
        }
    }
}

/** Classique, Sprint, Survie and Double sens: two columns, one when the text is very large. */
@Composable
private fun Modes(state: AppViewModel, openClassic: () -> Unit, playMode: (PlayMode) -> Unit) {
    val runs = remember(state.progress) { PlayMode.entries.filter { it != PlayMode.SPRINT && state.local.loadRun(it)?.finished == false }.toSet() }
    val tiles: List<@Composable (Modifier) -> Unit> = listOf(
        { m -> ModeTile(Icons.Filled.AllInclusive, Palette.foreground, "Classique", "Jouez sans limite.", "${state.progress.correctAnswers} mots trouvés", false, m, openClassic) },
    ) + PlayMode.entries.map { mode ->
        { m: Modifier -> ModeTile(mode.icon, mode.tint, mode.title, mode.tagline, recordLine(state, mode), mode in runs, m) { playMode(mode) } }
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Kicker("Autres modes", Palette.tertiary, Modifier.padding(start = 4.dp, top = 6.dp))
        val columns = if (LocalDensity.current.fontScale > 1.5f) 1 else 2
        tiles.chunked(columns).forEach { row ->
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                row.forEach { tile -> tile(Modifier.weight(1f).fillMaxHeight()) }
            }
        }
    }
}

private fun recordLine(state: AppViewModel, mode: PlayMode): String {
    val records = state.progress.records(mode)
    if (records.total(ModeStat.GAMES) == 0) return "Première partie"
    return when (mode) {
        PlayMode.SURVIVAL -> "Record ${records.best(ModeStat.WORDS)} mots"
        else -> "Record ${Format.number(records.best(ModeStat.SCORE))} pts"
    }
}

val PlayMode.icon: ImageVector get() = when (this) {
    PlayMode.SPRINT -> Icons.Filled.Bolt
    PlayMode.SURVIVAL -> Icons.Filled.Favorite
    PlayMode.DUO -> Icons.Filled.ViewAgenda
}
/** A quiet tint per mode, only on its glyph. */
val PlayMode.tint: Color get() = when (this) {
    PlayMode.SPRINT -> Palette.mint
    PlayMode.SURVIVAL -> Palette.red
    PlayMode.DUO -> Color(0xFF9EB5FF)
}
val PlayMode.tagline: String get() = when (this) {
    PlayMode.SPRINT -> "90 secondes pour battre votre record."
    PlayMode.SURVIVAL -> "Jusqu’où irez-vous avec 3 vies ?"
    PlayMode.DUO -> "Deux mots, les mêmes consonnes."
}

@Composable
private fun ModeTile(icon: ImageVector, tint: Color, title: String, tagline: String, detail: String, inProgress: Boolean, modifier: Modifier, open: () -> Unit) {
    val haptics = rememberHaptics()
    Surface({ haptics.selection(); open() }, modifier.heightIn(min = 150.dp), shape = RoundedCornerShape(26.dp), color = Palette.surface.copy(alpha = 0.82f),
        border = androidx.compose.foundation.BorderStroke(1.dp, Brush.verticalGradient(listOf(Palette.border, Palette.line)))) {
        Column(Modifier.padding(16.dp).semantics(mergeDescendants = true) {
            contentDescription = "$title. $tagline $detail" + if (inProgress) ". Partie en cours" else ""
        }) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(34.dp).background(tint.copy(alpha = 0.12f), CircleShape).border(1.dp, tint.copy(alpha = 0.25f), CircleShape), contentAlignment = Alignment.Center) {
                    Icon(icon, null, Modifier.size(17.dp), tint = tint)
                }
                Spacer(Modifier.weight(1f))
                if (inProgress) Text("En cours", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = Palette.mint,
                    modifier = Modifier.background(Palette.mint.copy(alpha = 0.12f), RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 3.dp))
            }
            Text(title, fontSize = 18.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 14.dp))
            Text(tagline, fontSize = 13.sp, color = Palette.secondary, modifier = Modifier.padding(top = 3.dp))
            Spacer(Modifier.weight(1f).heightIn(min = 12.dp))
            Text(detail, fontSize = 12.sp, fontWeight = FontWeight.Medium, color = Palette.tertiary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

private fun syncLabel(state: AppViewModel): String = when {
    state.uid == null -> "Hors connexion · progression gardée sur ce téléphone"
    state.isAnonymous -> "Sauvegardé en ligne · compte invité"
    else -> "Sauvegardé en ligne · " + (state.email ?: "compte permanent")
}

@Composable
private fun Header(state: AppViewModel) {
    Row(Modifier.fillMaxWidth().padding(top = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text("Bonjour,", color = Palette.secondary)
            Text(state.progress.username, style = MaterialTheme.typography.headlineMedium, maxLines = 1)
        }
        val streak = state.streak
        Surface(shape = RoundedCornerShape(50), color = Palette.fill1) {
            Row(Modifier.padding(horizontal = 14.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.LocalFireDepartment, null, Modifier.size(16.dp), tint = if (streak > 0) Palette.accent else Palette.secondary)
                Text("$streak jour${if (streak > 1) "s" else ""}", fontWeight = FontWeight.SemiBold, fontSize = 14.sp, modifier = Modifier.padding(start = 6.dp))
            }
        }
        Spacer(Modifier.width(10.dp))
        Avatar(state.progress.username, state.avatar, 40.dp)
    }
}

@Composable
private fun DailyCard(state: AppViewModel, play: () -> Unit) {
    val today = DailySchedule.key()
    val attempt = state.progress.attempts.firstOrNull { it.dailyKey == today }
    // The consonants show only once the daily card is locked, so the clock is already running.
    val started = state.progress.dailyStarted[today]?.let { state.card(it) }
    SectionCard(radius = 38.dp, padding = 24.dp) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Kicker("Mot du jour", Palette.foreground, Modifier.weight(1f))
            Text(LocalDate.now(DailySchedule.zone).format(DateTimeFormatter.ofPattern("EEE d MMM", Locale.FRENCH)), style = MaterialTheme.typography.bodySmall, color = Palette.tertiary)
        }
        if (attempt != null) {
            val card = state.card(attempt.cardID)
            Text(highlighted((card?.wordFull ?: "").uppercase()), fontSize = 32.sp, fontWeight = FontWeight.Black, letterSpacing = 2.6.sp, maxLines = 1,
                modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 22.dp, bottom = 4.dp))
            Text(if (attempt.correct) "Trouvé en ${Format.clock(attempt.timeMs)} · +${attempt.points} pts" else "Raté. Un nouveau mot arrive à minuit.",
                color = Palette.secondary, modifier = Modifier.align(Alignment.CenterHorizontally))
            Row(Modifier.padding(top = 20.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Surface(Modifier.weight(1f).height(56.dp), shape = RoundedCornerShape(20.dp), color = Palette.fill1) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                        Text("PROCHAIN MOT", fontSize = 11.sp, letterSpacing = 0.9.sp, color = Palette.tertiary)
                        Countdown()
                    }
                }
                val context = LocalContext.current
                FilledTonalButton({ Share.result(context, attempt, card, GameMode.DAILY) }, Modifier.height(56.dp), shape = RoundedCornerShape(20.dp)) {
                    Icon(Icons.Filled.Share, null, Modifier.size(18.dp)); Text("Partager", Modifier.padding(start = 8.dp))
                }
            }
        } else {
            val consonants = started?.wordNoVowels
            Text(consonants ?: "· · ·", style = Type.serif(if ((consonants?.length ?: 0) > 7) 60 else 92), letterSpacing = 5.sp, maxLines = 1,
                color = if (consonants == null) Palette.tertiary else Palette.foreground,
                modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 22.dp))
            Box(Modifier.align(Alignment.CenterHorizontally).padding(vertical = 18.dp).width(36.dp)) { Divider() }
            Text(if (consonants == null) "Un mot, un indice, un chrono. À vous de jouer." else "Votre chrono tourne. Reprenez la partie.",
                style = Type.serifItalic(21), textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
            Text(if (state.uid == null) "Connectez-vous à Internet pour jouer le mot du jour" else "Le même mot pour tous, une seule partie classée par jour",
                style = MaterialTheme.typography.bodySmall, color = Palette.tertiary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = 8.dp))
            PrimaryButton(if (consonants == null) "Jouer" else "Reprendre", Modifier.padding(top = 20.dp), onClick = play)
        }
    }
}

@Composable
private fun Countdown() {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(1000); now = System.currentTimeMillis() } }
    val seconds = Duration.between(Instant.ofEpochMilli(now), DailySchedule.nextDay(Instant.ofEpochMilli(now))).seconds
    Text(Format.countdown(seconds), fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
}

@Composable
private fun ClassicCard(state: AppViewModel, play: (Category?, Difficulty?) -> Unit) {
    var category by rememberSaveable { mutableStateOf<Category?>(null) }
    var difficulty by rememberSaveable { mutableStateOf<Difficulty?>(null) }
    val score = state.progress.score
    val level = score / 1000 + 1; val into = score % 1000
    Column(Modifier.padding(start = 24.dp, end = 24.dp, bottom = 28.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Kicker("Classique", modifier = Modifier.weight(1f))
            Text("${state.progress.correctAnswers} mots trouvés", style = MaterialTheme.typography.bodySmall, color = Palette.tertiary)
        }
        Text("Jouez sans limite", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 10.dp))
        Row(Modifier.padding(top = 16.dp)) {
            Text("Niveau $level", style = MaterialTheme.typography.bodySmall, color = Palette.secondary, modifier = Modifier.weight(1f))
            Text("${1000 - into} pts avant le niveau ${level + 1}", style = MaterialTheme.typography.bodySmall, color = Palette.secondary)
        }
        LevelBar(into / 1000f, Modifier.padding(top = 8.dp))
        Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterMenu(category?.label ?: "Toutes catégories", listOf<Category?>(null) + Category.entries, { it?.label ?: "Toutes catégories" }) { category = it }
            FilterMenu(difficulty?.label ?: "Toutes difficultés", listOf<Difficulty?>(null) + Difficulty.entries, { it?.label ?: "Toutes difficultés" }) { difficulty = it }
        }
        PrimaryButton("Lancer une partie", Modifier.padding(top = 20.dp)) { play(category, difficulty) }
    }
}

@Composable
private fun <T> FilterMenu(title: String, items: List<T>, label: (T) -> String, select: (T) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        AssistChip({ open = true }, { Text(title, maxLines = 1) }, trailingIcon = { Icon(Icons.Filled.ArrowDropDown, null) },
            shape = RoundedCornerShape(50), colors = AssistChipDefaults.assistChipColors(containerColor = Palette.fill1))
        DropdownMenu(open, { open = false }) {
            items.forEach { item -> DropdownMenuItem({ Text(label(item)) }, { select(item); open = false }) }
        }
    }
}
