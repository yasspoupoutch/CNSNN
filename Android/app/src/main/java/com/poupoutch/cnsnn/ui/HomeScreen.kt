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
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
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
import com.poupoutch.cnsnn.core.ClassicLevel
import com.poupoutch.cnsnn.core.DailySchedule
import com.poupoutch.cnsnn.core.Difficulty
import com.poupoutch.cnsnn.core.Format
import com.poupoutch.cnsnn.core.GameMode
import com.poupoutch.cnsnn.share.Share
import com.poupoutch.cnsnn.state.AppViewModel
import androidx.compose.foundation.clickable
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.EventRepeat
import com.poupoutch.cnsnn.core.CatchUp
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
    var catchUp by rememberSaveable { mutableStateOf(false) }
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
        DailyCard(state, today) { play(GameMode.DAILY, null, null) }
        val missed = remember(today, state.progress, state.catchUpDone) { CatchUp.toPlay(state.catchUpDays()) }
        if (missed > 0) CatchUpRow(missed) { catchUp = true }
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
    if (catchUp) {
        val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        val scope = rememberCoroutineScope()
        ModalBottomSheet({ catchUp = false }, sheetState = sheet, containerColor = Palette.surfaceHigh) {
            CatchUpSheet(state) { day ->
                scope.launch { sheet.hide() }.invokeOnCompletion { catchUp = false; playCatchUp(day) }
            }
        }
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
private fun DailyCard(state: AppViewModel, today: String, play: () -> Unit) {
    val attempt = state.progress.attempts.firstOrNull { it.dailyKey == today }
    // The consonants show only once the daily card is locked, so the clock is already running.
    val started = state.progress.dailyStarted[today]?.let { state.card(it) }
    // Compact, so the challenge and the modes stay on screen.
    SectionCard(Modifier.tutorialTarget(TutorialTarget.DAILY), radius = 28.dp, padding = 18.dp) {
        if (attempt != null) {
            val card = state.card(attempt.cardID)
            val context = LocalContext.current
            // Three rows: the kicker, the word on the whole width (smaller if long), then the time and
            // the countdown beside Classement and Partager, so nothing gets squeezed into a column.
            DailyFoundTitle((card?.wordFull ?: "").uppercase(), attempt.correct)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 6.dp)) {
                Column(Modifier.weight(1f)) {
                    Text(if (attempt.correct) Format.clock(attempt.timeMs) else "Raté cette fois",
                        fontSize = 13.sp, color = Palette.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Countdown()
                }
                FilledTonalButton({ state.leaderboardRequest++ }, Modifier.height(40.dp), shape = RoundedCornerShape(20.dp),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp)) { Text("Classement", fontWeight = FontWeight.SemiBold, maxLines = 1, softWrap = false) }
                androidx.compose.material3.IconButton({ Share.result(context, attempt, card, GameMode.DAILY) }) { Icon(Icons.Filled.Share, "Partager") }
            }
        } else {
            val consonants = started?.wordNoVowels
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Kicker("Mot du jour", Palette.foreground)
                        Text(LocalDate.now(DailySchedule.zone).format(DateTimeFormatter.ofPattern("EEE d MMM", Locale.FRENCH)), style = MaterialTheme.typography.bodySmall,
                            color = Palette.tertiary, maxLines = 1, modifier = Modifier.padding(start = 8.dp))
                    }
                    Text(consonants ?: "· · ·", style = Type.serif(if (consonants == null) 34 else 46), letterSpacing = if (consonants == null) 6.sp else 3.sp, maxLines = 1,
                        softWrap = false, color = if (consonants == null) Palette.tertiary else Palette.foreground, modifier = Modifier.padding(top = 4.dp)
                            .semantics { contentDescription = consonants?.let { "Consonnes : " + it.toList().joinToString(", ") } ?: "Mot masqué" })
                }
                Button(play, Modifier.height(54.dp).width(128.dp).tutorialTarget(TutorialTarget.PLAY), shape = RoundedCornerShape(27.dp)) {
                    Text(if (consonants == null) "Jouer" else "Reprendre", fontWeight = FontWeight.Bold, fontSize = 17.sp, maxLines = 1)
                }
            }
            Text(if (consonants == null) "Un mot, un indice, un chrono." else "Votre chrono tourne. Reprenez la partie.",
                style = Type.serifItalic(18), color = Palette.secondary, modifier = Modifier.padding(top = 8.dp)
                    .semantics { contentDescription = (if (consonants == null) "Un mot, un indice, un chrono." else "Votre chrono tourne.") +
                        if (state.uid == null) " Connectez-vous à Internet pour jouer le mot du jour." else " Le même mot pour tous, une seule partie classée par jour." })
        }
    }
}

/** The kicker with "✓ trouvé", then the word on the card's whole width. */
@Composable
internal fun DailyFoundTitle(word: String, correct: Boolean) {
    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Kicker("Mot du jour", Palette.foreground)
            if (correct) Text("✓ trouvé", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Palette.mint, maxLines = 1, softWrap = false,
                modifier = Modifier.padding(start = 8.dp).testTag("dailyFound"))
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

/** Rattrapage: the week's missed daily words, for fun. */
@Composable
private fun CatchUpRow(missed: Int, open: () -> Unit) {
    val plural = if (missed > 1) "s" else ""
    SectionCard(Modifier.clickable(onClickLabel = "Rattraper la semaine", onClick = open).testTag("catchUp.open"), padding = 16.dp, radius = 24.dp) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.EventRepeat, null, tint = Palette.secondary)
            Column(Modifier.weight(1f).padding(start = 14.dp)) {
                Text("Rattraper la semaine", fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                Text("$missed mot$plural du jour manqué$plural depuis lundi", fontSize = 13.sp, color = Palette.secondary)
            }
            Icon(Icons.Filled.ChevronRight, null, tint = Palette.tertiary)
        }
    }
}

/**
 * Rattrapage: the days of the week before today. Played days are done; the others can be played
 * once, for fun, outside every ranking. A day opens once it is over everywhere (14 h in Paris the next day).
 */
@Composable
private fun CatchUpSheet(state: AppViewModel, play: (String) -> Unit) {
    // Days played on another phone, found on the server when the sheet opens.
    var playedElsewhere by remember { mutableStateOf(emptySet<String>()) }
    LaunchedEffect(state.uid) {
        val uid = state.uid ?: return@LaunchedEffect
        state.catchUpDays().filter { it.status == CatchUp.Status.Open }.forEach { day ->
            if (runCatching { state.cloud.dailyResult(uid, day.key) }.getOrNull() != null) playedElsewhere = playedElsewhere + day.key
        }
    }
    val days = state.catchUpDays().map { if (it.key in playedElsewhere) it.copy(status = CatchUp.Status.Played) else it }
    Column(Modifier.padding(start = 24.dp, end = 24.dp, bottom = 28.dp)) {
        Kicker("Rattrapage")
        Text("Les mots de la semaine", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 10.dp))
        Text("Pour le plaisir : un mot rattrapé ne compte pas au classement.", color = Palette.secondary, fontSize = 14.sp, modifier = Modifier.padding(top = 6.dp))
        SectionCard(Modifier.padding(top = 18.dp), padding = 0.dp, radius = 24.dp) {
            days.forEachIndexed { index, day ->
                if (index > 0) Divider()
                Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 18.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(Format.day(day.key), fontWeight = FontWeight.SemiBold, fontSize = 16.sp, modifier = Modifier.weight(1f))
                    when (val status = day.status) {
                        CatchUp.Status.Played -> Text("joué le jour même", fontSize = 13.sp, color = Palette.tertiary)
                        is CatchUp.Status.Done -> Text(if (status.found) "✓ rattrapé" else "pas trouvé", fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                            color = if (status.found) Palette.mint else Palette.secondary)
                        is CatchUp.Status.Later -> Text("dès " + status.at.atZone(DailySchedule.zone).format(DateTimeFormatter.ofPattern("H'h'mm")),
                            fontSize = 13.sp, color = Palette.tertiary)
                        CatchUp.Status.Open -> Button({ play(day.key) }, Modifier.height(40.dp), shape = RoundedCornerShape(20.dp)) {
                            Text("Jouer", fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
        }
    }
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
