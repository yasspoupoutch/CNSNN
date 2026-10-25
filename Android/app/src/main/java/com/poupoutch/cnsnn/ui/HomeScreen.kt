package com.poupoutch.cnsnn.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.RowScope
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
import androidx.compose.ui.platform.testTag
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Leaderboard
import androidx.compose.material3.Button
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
import com.poupoutch.cnsnn.core.ClassicLevel
import com.poupoutch.cnsnn.core.DailySchedule
import com.poupoutch.cnsnn.core.Difficulty
import com.poupoutch.cnsnn.core.Format
import com.poupoutch.cnsnn.core.GameMode
import com.poupoutch.cnsnn.share.Share
import com.poupoutch.cnsnn.state.AppViewModel
import androidx.compose.foundation.clickable
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.ui.draw.alpha
import com.poupoutch.cnsnn.core.CatchUp
import com.poupoutch.cnsnn.core.DailyScore
import kotlinx.coroutines.delay
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(state: AppViewModel, play: (GameMode, Category?, Difficulty?) -> Unit, playMode: (PlayMode) -> Unit, playChallenge: (String) -> Unit,
               playCatchUp: (String) -> Unit) {
    var classic by rememberSaveable { mutableStateOf(false) }
    /** The missed day the player tapped in the week strip, asked before its clock starts. */
    var catchUp by rememberSaveable { mutableStateOf<String?>(null) }
    var challenges by rememberSaveable { mutableStateOf(false) }
    // "Défier un ami" on the daily result opens the sheet once back here.
    var seenRequest by rememberSaveable { mutableStateOf(state.challengeRequest) }
    LaunchedEffect(state.challengeRequest) { if (state.challengeRequest != seenRequest) { seenRequest = state.challengeRequest; challenges = true } }
    LaunchedEffect(state.inviteCode) { if (state.inviteCode != null) challenges = true }
    LaunchedEffect(state.uid) { state.refreshChallenges() }
    // The day on screen, moved on at midnight and whenever the app comes back (a notification tap
    // the next morning), so yesterday's found word never stays up.
    var today by remember { mutableStateOf(DailySchedule.key()) }
    LaunchedEffect(today) {
        kotlinx.coroutines.delay(maxOf(1_000L, DailySchedule.nextDay().toEpochMilli() - System.currentTimeMillis() + 1_000L))
        today = DailySchedule.key()
    }
    val lifecycle = androidx.compose.ui.platform.LocalLifecycleOwner.current.lifecycle
    androidx.compose.runtime.DisposableEffect(lifecycle) {
        val observer = androidx.lifecycle.LifecycleEventObserver { _, event ->
            if (event == androidx.lifecycle.Lifecycle.Event.ON_RESUME) { today = DailySchedule.key(); state.refreshChallengesSoon() }
        }
        lifecycle.addObserver(observer); onDispose { lifecycle.removeObserver(observer) }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).statusBarsPadding().padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Header(state)
        DailyCard(state, today, play = { play(GameMode.DAILY, null, null) }, catchUp = { catchUp = it })
        Modes(state, openClassic = { classic = true }, playMode = playMode, openChallenges = { challenges = true }, playChallenge = { playChallenge(it.id) })
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
    catchUp?.let { day ->
        AlertDialog({ catchUp = null },
            confirmButton = { TextButton({ catchUp = null; playCatchUp(day) }, Modifier.testTag("catchUp.play")) { Text("Jouer") } },
            dismissButton = { TextButton({ catchUp = null }) { Text("Annuler") } },
            title = { Text("Rattraper le mot du ${Format.weekday(day)} ?") },
            text = { Text("Il compte au classement avec 5 minutes en plus. Le chrono démarre dès l’ouverture.") },
            containerColor = Palette.surfaceHigh)
    }
    if (challenges) {
        val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        val scope = rememberCoroutineScope()
        ModalBottomSheet({ challenges = false }, sheetState = sheet, containerColor = Palette.surfaceHigh) {
            ChallengeSheet(state) { c ->
                scope.launch { sheet.hide() }.invokeOnCompletion { challenges = false; playChallenge(c.id) }
            }
        }
    }
}

/** Classique, Sprint, Survie and Double sens: two columns, one when the text is very large. */
@Composable
private fun Modes(state: AppViewModel, openClassic: () -> Unit, playMode: (PlayMode) -> Unit, openChallenges: () -> Unit, playChallenge: (com.poupoutch.cnsnn.core.Challenge) -> Unit) {
    val runs = remember(state.progress) { PlayMode.entries.filter { it != PlayMode.SPRINT && state.local.loadRun(it)?.finished == false }.toSet() }
    val tiles = listOf(Tile(Icons.Filled.AllInclusive, Palette.foreground, "Classique", "Jouez sans limite.", "${state.progress.correctAnswers} mots trouvés", false, openClassic)) +
        PlayMode.entries.map { mode -> Tile(mode.icon, mode.tint, mode.title, mode.tagline, recordLine(state, mode), mode in runs) { playMode(mode) } }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Kicker("Jouer aussi", Palette.tertiary, Modifier.padding(start = 4.dp, top = 4.dp))
        ChallengeTile(state, openChallenges, playChallenge)
        val columns = if (LocalDensity.current.fontScale > 1.5f) 1 else 2
        tiles.chunked(columns).forEach { row ->
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { t -> ModeTile(t.icon, t.tint, t.title, t.tagline, t.detail, t.inProgress, Modifier.weight(1f).fillMaxHeight(), t.open) }
            }
        }
    }
}

private class Tile(val icon: ImageVector, val tint: Color, val title: String, val tagline: String, val detail: String, val inProgress: Boolean, val open: () -> Unit)

private fun recordLine(state: AppViewModel, mode: PlayMode): String {
    val records = state.progress.records(mode)
    if (records.total(ModeStat.GAMES) == 0) return "Première partie"
    return "Record " + recordText(mode, records.best(mode.mainRecord))
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
    Surface({ haptics.selection(); open() }, modifier.heightIn(min = 112.dp), shape = RoundedCornerShape(22.dp), color = Palette.surface.copy(alpha = 0.82f),
        border = androidx.compose.foundation.BorderStroke(1.dp, Brush.verticalGradient(listOf(Palette.border, Palette.line)))) {
        Column(Modifier.padding(horizontal = 14.dp, vertical = 12.dp).semantics(mergeDescendants = true) {
            contentDescription = "$title. $tagline $detail" + if (inProgress) ". Partie en cours" else ""
        }) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(30.dp).background(tint.copy(alpha = 0.12f), CircleShape).border(1.dp, tint.copy(alpha = 0.25f), CircleShape), contentAlignment = Alignment.Center) {
                    Icon(icon, null, Modifier.size(16.dp), tint = tint)
                }
                Spacer(Modifier.weight(1f))
                if (inProgress) Text("En cours", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = Palette.mint,
                    modifier = Modifier.background(Palette.mint.copy(alpha = 0.12f), RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 3.dp))
            }
            Text(title, fontSize = 16.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 8.dp))
            Text(tagline, fontSize = 12.sp, lineHeight = 16.sp, color = Palette.secondary, maxLines = 2, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(top = 2.dp))
            Spacer(Modifier.weight(1f).heightIn(min = 8.dp))
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
private fun DailyCard(state: AppViewModel, today: String, play: () -> Unit, catchUp: (String) -> Unit) {
    val attempt = state.progress.attempts.firstOrNull { it.dailyKey == today }
    // The consonants show only once the daily card is locked, so the clock is already running.
    val started = state.progress.dailyStarted[today]?.let { state.card(it) }
    val context = LocalContext.current
    // One card for the day: Classement and Partager at the top right, the word with Jouer, then the week.
    val actions: @Composable RowScope.() -> Unit = {
        if (state.uid != null || attempt != null) CornerIcon(Icons.Filled.Leaderboard, "Classement") { state.leaderboardRequest++ }
        if (attempt != null) CornerIcon(Icons.Filled.Share, "Partager") { Share.result(context, attempt, state.card(attempt.cardID), GameMode.DAILY) }
    }
    SectionCard(Modifier.tutorialTarget(TutorialTarget.DAILY), radius = 28.dp, padding = 18.dp) {
        if (attempt != null) {
            val card = state.card(attempt.cardID)
            DailyFoundTitle((card?.wordFull ?: "").uppercase(), attempt.correct, actions)
            // A day counts 10 minutes at most: past that, the real time stays here with what the ranking counts.
            Text(if (attempt.correct) Format.clock(attempt.timeMs) + (if (attempt.timeMs >= DailyScore.MISSED_MS) " · compté " + Format.clock(DailyScore.MISSED_MS) + " au classement" else "") else "Raté cette fois",
                fontSize = 13.sp, color = Palette.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 4.dp))
            Countdown()
        } else {
            val consonants = started?.wordNoVowels
            DailyHeader(found = false, actions = actions)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp), modifier = Modifier.padding(top = 4.dp)) {
                Text(consonants ?: "· · ·", style = Type.serif(if (consonants == null) 34 else 46), letterSpacing = if (consonants == null) 6.sp else 3.sp, maxLines = 1,
                    softWrap = false, color = if (consonants == null) Palette.tertiary else Palette.foreground, modifier = Modifier.weight(1f)
                        .semantics { contentDescription = consonants?.let { "Consonnes : " + it.toList().joinToString(", ") } ?: "Mot masqué" })
                Button(play, Modifier.height(54.dp).width(128.dp).tutorialTarget(TutorialTarget.PLAY), shape = RoundedCornerShape(27.dp)) {
                    Text(if (consonants == null) "Jouer" else "Reprendre", fontWeight = FontWeight.Bold, fontSize = 17.sp, maxLines = 1)
                }
            }
            Text(if (consonants == null) "Un mot, un indice, un chrono." else "Votre chrono tourne. Reprenez la partie.",
                style = Type.serifItalic(18), color = Palette.secondary, modifier = Modifier.padding(top = 8.dp)
                    .semantics { contentDescription = (if (consonants == null) "Un mot, un indice, un chrono." else "Votre chrono tourne.") +
                        if (state.uid == null) " Connectez-vous à Internet pour jouer le mot du jour." else " Le même mot pour tous, une seule partie classée par jour." })
        }
        if (state.uid != null) {
            Box(Modifier.padding(top = 16.dp, bottom = 12.dp).fillMaxWidth().height(1.dp).background(Palette.border))
            WeekRow(state, today, playToday = play, catchUp = catchUp)
        }
    }
}

/** A small round button in the card's top right corner, with a 48 dp touch area. */
@Composable
private fun CornerIcon(icon: ImageVector, label: String, onClick: () -> Unit) {
    Box(Modifier.size(48.dp).clickable(onClickLabel = label, onClick = onClick).semantics { contentDescription = label }, contentAlignment = Alignment.Center) {
        Box(Modifier.size(36.dp).background(Palette.fill1, RoundedCornerShape(18.dp)).border(1.dp, Palette.border, RoundedCornerShape(18.dp)),
            contentAlignment = Alignment.Center) {
            Icon(icon, null, Modifier.size(18.dp), tint = Palette.foreground)
        }
    }
}

/** "Mot du jour" with the date (or "✓ trouvé"), and the corner buttons on the right. */
@Composable
private fun DailyHeader(found: Boolean, actions: @Composable RowScope.() -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
        Kicker("Mot du jour", Palette.foreground)
        if (found) Text("✓ trouvé", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Palette.mint, maxLines = 1, softWrap = false,
            modifier = Modifier.padding(start = 8.dp).testTag("dailyFound"))
        else Text(LocalDate.now(DailySchedule.zone).format(DateTimeFormatter.ofPattern("EEE d MMM", Locale.FRENCH)), style = MaterialTheme.typography.bodySmall,
            color = Palette.tertiary, maxLines = 1, modifier = Modifier.padding(start = 8.dp))
        Spacer(Modifier.weight(1f))
        actions()
    }
}

/** The kicker with "✓ trouvé", then the word on the card's whole width. */
@Composable
internal fun DailyFoundTitle(word: String, correct: Boolean, actions: @Composable RowScope.() -> Unit = {}) {
    Column {
        if (correct) DailyHeader(found = true, actions = actions)
        else Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
            Kicker("Mot du jour", Palette.foreground); Spacer(Modifier.weight(1f)); actions()
        }
        BoxWithConstraints(Modifier.fillMaxWidth().padding(top = 4.dp)) {
            // About 0.68 em per serif capital (a margin): shrink so the whole word fits, never under 22 sp.
            val size = with(LocalDensity.current) { (maxWidth.toPx() / (maxOf(word.length, 1) * 0.68f)).toSp().value }.coerceIn(22f, 40f)
            Text(highlighted(word), style = Type.serif(40).copy(fontSize = size.sp, lineHeight = (size * 1.1f).sp), maxLines = 1, softWrap = false,
                overflow = TextOverflow.Ellipsis, modifier = Modifier.testTag("dailyWord"))
        }
    }
}

@Composable
private fun Countdown() {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(1000); now = System.currentTimeMillis() } }
    val seconds = Duration.between(Instant.ofEpochMilli(now), DailySchedule.nextDay(Instant.ofEpochMilli(now))).seconds
    Text("Prochain mot dans " + Format.countdown(seconds), fontSize = 12.sp, color = Palette.tertiary, maxLines = 2)
}

/**
 * This week's daily words, Monday to Sunday, like the 7 days in Stats: green check for a found word, red
 * cross for a lost one. A missed day can be caught up: it counts in the ranking with 5 minutes more.
 */
@Composable
private fun WeekRow(state: AppViewModel, today: String, playToday: () -> Unit, catchUp: (String) -> Unit) {
    // Days played on another phone, found on the server (day to found).
    var playedElsewhere by remember { mutableStateOf(emptyMap<String, Boolean>()) }
    LaunchedEffect(state.uid, today) {
        val uid = state.uid ?: return@LaunchedEffect
        state.catchUpDays().filter { it.status == CatchUp.Status.Open && it.key !in playedElsewhere }.forEach { day ->
            runCatching { state.cloud.dailyResult(uid, day.key) }.getOrNull()?.let { playedElsewhere = playedElsewhere + (day.key to it.first.correct) }
        }
    }
    val days = remember(today, state.progress, playedElsewhere) {
        state.dailyWeek().map { day -> playedElsewhere[day.key]?.let { day.copy(status = CatchUp.Status.Played(it)) } ?: day }
    }
    val letters = listOf("L", "M", "M", "J", "V", "S", "D")
    Column {
        Row {
            days.forEachIndexed { index, day ->
                val status = day.status
                val action: (() -> Unit)? = when (status) {
                    CatchUp.Status.Open -> { { catchUp(day.key) } }
                    CatchUp.Status.Today -> playToday
                    else -> null
                }
                Column(Modifier.weight(1f).then(if (action != null) Modifier.clickable(onClickLabel = "Jouer", onClick = action) else Modifier)
                    .testTag("week.${day.key}").semantics(mergeDescendants = true) { contentDescription = Format.day(day.key) + " : " + spoken(status) },
                    horizontalAlignment = Alignment.CenterHorizontally) {
                    val isToday = status == CatchUp.Status.Today
                    Box(Modifier.size(30.dp).alpha(if (status == CatchUp.Status.Coming) 0.45f else 1f)
                        .background(when (status) { is CatchUp.Status.Played -> if (status.found) Palette.mint else Palette.red; else -> Palette.fill1 }, RoundedCornerShape(10.dp))
                        .border(if (isToday) 1.5.dp else 1.dp, if (isToday) Palette.foreground else Palette.border, RoundedCornerShape(10.dp)),
                        contentAlignment = Alignment.Center) {
                        // A symbol as well as the colour, so the week reads without colour vision.
                        when (status) {
                            is CatchUp.Status.Played -> Icon(if (status.found) Icons.Filled.Check else Icons.Filled.Close, null, Modifier.size(18.dp), tint = Palette.ink)
                            CatchUp.Status.Open -> Icon(Icons.Filled.PlayArrow, null, Modifier.size(18.dp), tint = Palette.foreground)
                            is CatchUp.Status.Later -> Icon(Icons.Filled.Schedule, null, Modifier.size(16.dp), tint = Palette.tertiary)
                            else -> {}
                        }
                    }
                    Text(letters[index], fontSize = 11.sp, fontWeight = if (isToday) FontWeight.Bold else FontWeight.Normal,
                        color = if (isToday) Palette.foreground else Palette.tertiary, modifier = Modifier.padding(top = 4.dp))
                }
            }
        }
        Text(weekLine(days), fontSize = 12.sp, color = Palette.tertiary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = 8.dp))
    }
}

private fun hour(at: Instant): String = at.atZone(DailySchedule.zone).format(DateTimeFormatter.ofPattern("H'h'mm"))
private fun weekLine(days: List<CatchUp.Day>): String {
    val open = days.count { it.status == CatchUp.Status.Open }
    if (open > 0) return "$open jour${if (open > 1) "s" else ""} à rattraper (+5 min)"
    days.firstNotNullOfOrNull { it.status as? CatchUp.Status.Later }?.let { return "À rattraper dès " + hour(it.at) }
    val found = days.count { it.status == CatchUp.Status.Played(true) }
    return "$found mot${if (found > 1) "s" else ""} trouvé${if (found > 1) "s" else ""}"
}
private fun spoken(status: CatchUp.Status): String = when (status) {
    is CatchUp.Status.Played -> if (status.found) "trouvé" else "raté"
    CatchUp.Status.Open -> "manqué, à rattraper avec 5 minutes en plus"
    is CatchUp.Status.Later -> "manqué, à rattraper dès " + hour(status.at)
    CatchUp.Status.Today -> "aujourd’hui, à jouer"
    CatchUp.Status.Coming -> "à venir"
}

@Composable
private fun ClassicCard(state: AppViewModel, play: (Category?, Difficulty?) -> Unit) {
    var category by rememberSaveable { mutableStateOf<Category?>(null) }
    var difficulty by rememberSaveable { mutableStateOf<Difficulty?>(null) }
    val level = state.progress.level; val into = state.progress.levelInto
    Column(Modifier.padding(start = 24.dp, end = 24.dp, bottom = 28.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Kicker("Classique", modifier = Modifier.weight(1f))
            Text("${state.progress.correctAnswers} mots trouvés", style = MaterialTheme.typography.bodySmall, color = Palette.tertiary)
        }
        Text("Jouez sans limite", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 10.dp))
        Row(Modifier.padding(top = 16.dp)) {
            Text("Niveau $level", style = MaterialTheme.typography.bodySmall, color = Palette.secondary, modifier = Modifier.weight(1f))
            val left = ClassicLevel.WORDS_PER_LEVEL - into
            Text("$left mot${if (left > 1) "s" else ""} avant le niveau ${level + 1}", style = MaterialTheme.typography.bodySmall, color = Palette.secondary)
        }
        LevelBar(into / ClassicLevel.WORDS_PER_LEVEL.toFloat(), Modifier.padding(top = 8.dp))
        // Every choice is shown at once, so players see they can pick a theme or a level.
        Kicker("Catégorie", color = Palette.secondary, modifier = Modifier.padding(top = 22.dp, bottom = 4.dp))
        ChipRow(listOf<Category?>(null) + Category.entries, category, { it?.label ?: "Toutes" }) { category = it }
        Kicker("Difficulté", color = Palette.secondary, modifier = Modifier.padding(top = 14.dp, bottom = 4.dp))
        ChipRow(listOf<Difficulty?>(null) + Difficulty.entries, difficulty, { it?.label ?: "Toutes" }) { difficulty = it }
        PrimaryButton("Lancer une partie", Modifier.padding(top = 20.dp)) { play(category, difficulty) }
    }
}

