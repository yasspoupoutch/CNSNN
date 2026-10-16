package com.poupoutch.cnsnn.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import com.poupoutch.cnsnn.core.Card
import com.poupoutch.cnsnn.core.DuoGame
import com.poupoutch.cnsnn.core.DuoRecord
import com.poupoutch.cnsnn.core.DuoWord
import com.poupoutch.cnsnn.core.Format
import com.poupoutch.cnsnn.core.ModeStat
import com.poupoutch.cnsnn.core.PlayMode
import com.poupoutch.cnsnn.core.SprintGame
import com.poupoutch.cnsnn.core.SurvivalGame
import com.poupoutch.cnsnn.core.records
import com.poupoutch.cnsnn.state.AppViewModel
import com.poupoutch.cnsnn.state.ModeViewModel
import kotlinx.coroutines.delay

/** Sprint, Survie and Double sens: the game board, keyboard and results of each mode. */
@Composable
fun ModeScreen(state: AppViewModel, mode: PlayMode, close: () -> Unit) {
    val game: ModeViewModel = viewModel()
    LaunchedEffect(Unit) { game.loadOnce(mode, state) }
    val haptics = rememberHaptics()
    var confirmQuit by remember { mutableStateOf(false) }
    // The Sprint clock never stops: back in the app, a Sprint whose time ran out ends at once.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_RESUME) game.tick(state) }
        lifecycle.addObserver(observer); onDispose { lifecycle.removeObserver(observer) }
    }
    if (mode == PlayMode.SPRINT) LaunchedEffect(Unit) {
        while (true) { delay(200); game.tick(state) }
    }
    val leave = { if (game.over || game.finished) close() else confirmQuit = true }
    BackHandler(onBack = leave)
    LaunchedEffect(game.mistakeTick) { if (game.mistakeTick > 0) haptics.retry() }
    LaunchedEffect(game.successTick) { if (game.successTick > 0) haptics.success() }

    Box(Modifier.fillMaxSize()) {
        AmbientBackground(dimmed = !game.over)
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(horizontal = 12.dp)) {
            TopBar(game, mode, leave)
            game.version // Recomposes on every move: the core games are plain objects.
            if (!game.over) when (mode) {
                PlayMode.SPRINT -> game.sprint?.let { SprintBoard(state, game, it) }
                PlayMode.SURVIVAL -> game.survival?.let { SurvivalBoard(state, game, it) }
                PlayMode.DUO -> game.duo?.let { DuoBoard(state, game, it) }
            }
        }
        AnimatedVisibility(game.over, enter = fadeIn(), exit = fadeOut()) {
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.42f)))
        }
        AnimatedVisibility(game.over, Modifier.align(Alignment.BottomCenter),
            enter = slideInVertically(spring(dampingRatio = 0.85f, stiffness = Spring.StiffnessMediumLow)) { it }, exit = slideOutVertically { it }) {
            ModeResult(state, game, replay = { haptics.selection(); game.begin(state) }, close = close)
        }
    }

    if (confirmQuit) AlertDialog({ confirmQuit = false },
        title = { Text(if (mode == PlayMode.SPRINT) "Arrêter le sprint ?" else "Quitter la partie ?") },
        text = { Text(when (mode) {
            PlayMode.SPRINT -> "La partie est comptée avec les mots déjà trouvés."
            PlayMode.SURVIVAL -> "Vous pouvez la reprendre plus tard depuis l’accueil, ou l’abandonner : elle sera comptée telle quelle."
            PlayMode.DUO -> "Vous pouvez la reprendre plus tard (le chrono continue), ou l’abandonner : les manches restantes compteront comme perdues."
        }) },
        confirmButton = {
            TextButton({ confirmQuit = false; game.quit(state) }) { Text(if (mode == PlayMode.SPRINT) "Arrêter" else "Abandonner", color = Palette.red) }
        },
        dismissButton = {
            Row {
                if (mode != PlayMode.SPRINT) TextButton({ confirmQuit = false; close() }) { Text("Plus tard") }
                TextButton({ confirmQuit = false }) { Text("Continuer") }
            }
        })
}

@Composable
private fun TopBar(game: ModeViewModel, mode: PlayMode, leave: () -> Unit) {
    game.version // The core games are plain objects: each part re-reads them after every move.
    Box(Modifier.fillMaxWidth().height(56.dp)) {
        IconButton(leave, Modifier.align(Alignment.CenterStart)) { Icon(Icons.Filled.Close, "Quitter") }
        Column(Modifier.align(Alignment.Center).semantics(mergeDescendants = true) { heading() }, horizontalAlignment = Alignment.CenterHorizontally) {
            Text(mode.title, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
            val duo = game.duo
            Text(when (mode) {
                PlayMode.SPRINT -> "90 secondes"
                PlayMode.SURVIVAL -> if (game.resumed) "Partie reprise" else "3 vies"
                PlayMode.DUO -> if (duo == null) "" else "Manche ${minOf(duo.round + 1, duo.duos.size)} sur ${duo.duos.size}"
            }, fontSize = 12.sp, color = Palette.tertiary)
        }
        Box(Modifier.align(Alignment.CenterEnd).padding(end = 4.dp)) {
            when (mode) {
                PlayMode.SPRINT -> Pill(Format.number(game.sprint?.found ?: 0), "Mots")
                PlayMode.SURVIVAL -> Hearts(game.survival?.lives ?: SurvivalGame.MAX_LIVES, game.lifeLostTick, game.lifeGainedTick)
                PlayMode.DUO -> {
                    var tick by remember { mutableIntStateOf(0) }
                    LaunchedEffect(Unit) { while (true) { delay(500); tick++ } }
                    tick
                    Pill(Format.clock(game.duo?.playMs(game.elapsedMs) ?: 0), "Chrono")
                }
            }
        }
    }
}

@Composable
internal fun Pill(value: String, label: String) {
    Surface(shape = RoundedCornerShape(50), color = Palette.fill1) {
        Text(value, fontWeight = FontWeight.Bold, fontSize = 14.sp, modifier = Modifier.padding(horizontal = 13.dp, vertical = 8.dp)
            .semantics { contentDescription = "$label : $value" })
    }
}

@Composable
private fun Hearts(lives: Int, lost: Int, gained: Int) {
    val reduce = rememberReduceMotion()
    val pulse = remember { Animatable(1f) }
    LaunchedEffect(lost, gained) {
        if (!reduce && (lost > 0 || gained > 0)) { pulse.snapTo(if (gained > 0 && lost == 0) 1.25f else 0.8f); pulse.animateTo(1f, spring(dampingRatio = 0.4f, stiffness = 400f)) }
    }
    Surface(shape = RoundedCornerShape(50), color = Palette.fill1) {
        Row(Modifier.padding(horizontal = 12.dp, vertical = 8.dp).semantics(mergeDescendants = true) { contentDescription = "$lives vie${if (lives > 1) "s" else ""} sur ${SurvivalGame.MAX_LIVES}" },
            horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            repeat(SurvivalGame.MAX_LIVES) { index ->
                val full = index < lives
                Icon(if (full) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder, null, Modifier.size(17.dp).scale(if (index == lives - 1 || index == lives) pulse.value else 1f),
                    tint = if (full) Palette.red else Palette.tertiary)
            }
        }
    }
}

// ---- Boards

@Composable
private fun ColumnScope.SprintBoard(state: AppViewModel, game: ModeViewModel, sprint: SprintGame) {
    game.version // The core games are plain objects: each part re-reads them after every move.
    SprintClock { sprint.remainingMs(game.elapsedMs) }
    Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Stat("${sprint.found}", if (sprint.found > 1) "mots" else "mot", Modifier.weight(1f))
        Stat("×${maxOf(1, sprint.streak)}", "combo", Modifier.weight(1f), highlight = sprint.streak > 1)
        var showGain by remember { mutableStateOf(false) }
        LaunchedEffect(game.successTick) { if (game.successTick > 0) { showGain = true; delay(900); showGain = false } }
        Stat(if (showGain) game.gain ?: "" else "${sprint.accuracy} %", if (showGain) "trouvé" else "précision", Modifier.weight(1f), highlight = showGain)
    }
    sprint.card?.let { Clue(it) }
    Controls(state, game, "Passer · −5 s", "Passer ce mot, 5 secondes de pénalité")
}

@Composable
private fun SprintClock(remaining: () -> Int) {
    // Only the clock re-reads the time five times a second, not the whole board and keyboard.
    var tick by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) { while (true) { delay(200); tick++ } }
    tick
    val remainingMs = remaining()
    val seconds = (remainingMs + 999) / 1000
    val low = remainingMs <= 10_000
    val haptics = rememberHaptics()
    val reduce = rememberReduceMotion()
    LaunchedEffect(seconds) { if (seconds in 1..5) haptics.key() }
    val progress by animateFloatAsState(remainingMs / SprintGame.DURATION_MS.toFloat(), tween(200), label = "clock")
    val beat by animateFloatAsState(if (low && !reduce && seconds % 2 == 0) 1.06f else 1f, tween(250), label = "beat")
    Row(Modifier.fillMaxWidth().padding(top = 6.dp, start = 4.dp, end = 4.dp).semantics(mergeDescendants = true) { contentDescription = "Temps restant : $seconds secondes" },
        verticalAlignment = Alignment.CenterVertically) {
        Text(Format.clock(seconds * 1000), fontWeight = FontWeight.Bold, fontSize = 17.sp, color = if (low) Palette.red else Palette.foreground,
            modifier = Modifier.width(56.dp).scale(beat))
        LinearProgressIndicator(progress = { progress }, Modifier.weight(1f).height(6.dp), color = if (low) Palette.red else Palette.foreground,
            trackColor = Palette.fill1, strokeCap = StrokeCap.Round, gapSize = 0.dp, drawStopIndicator = {})
    }
}

@Composable
private fun ColumnScope.SurvivalBoard(state: AppViewModel, game: ModeViewModel, survival: SurvivalGame) {
    game.version // The core games are plain objects: each part re-reads them after every move.
    Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Stat("${survival.found}", if (survival.found > 1) "mots trouvés" else "mot trouvé", Modifier.weight(1f))
        Stat("${survival.level}", "niveau", Modifier.weight(1f))
        Stat(survival.card?.difficulty?.label ?: "—", "difficulté", Modifier.weight(1f))
    }
    val left = SurvivalGame.BONUS_EVERY - survival.found % SurvivalGame.BONUS_EVERY
    Text(if (left == 1) "Encore 1 mot pour regagner une vie" else "Une vie regagnée tous les ${SurvivalGame.BONUS_EVERY} mots",
        fontSize = 12.sp, color = Palette.tertiary, modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 8.dp))
    survival.card?.let { Clue(it) }
    Controls(state, game, "Passer · −1 vie", "Passer ce mot, une vie en moins")
}

@Composable
private fun ColumnScope.DuoBoard(state: AppViewModel, game: ModeViewModel, duo: DuoGame) {
    game.version // The core games are plain objects: each part re-reads them after every move.
    val current = duo.duo ?: return
    Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
        val consonants = current.consonants
        Text(consonants, style = Type.serif(if (consonants.length > 4) 64 else 84), letterSpacing = 4.sp, maxLines = 1,
            modifier = Modifier.padding(top = 18.dp).semantics { contentDescription = "Consonnes : " + consonants.toList().joinToString(", ") })
        Text("Deux mots, les mêmes consonnes", fontSize = 12.sp, color = Palette.tertiary)
        Column(Modifier.padding(top = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            DuoClue(1, current.first, duo.found[duo.round][0], duo.roundComplete)
            DuoClue(2, current.second, duo.found[duo.round][1], duo.roundComplete)
        }
    }
    if (duo.roundComplete) {
        PrimaryButton(if (duo.finished) "Voir le résultat" else "Manche suivante", Modifier.padding(bottom = 12.dp)) { game.nextRound(state) }
    } else {
        AnswerLine(game.answer, game.mistakeTick, true)
        SkipChip("Passer la manche", "Passer la manche et voir les mots") { game.skip(state) }
        LetterKeyboard(press = { game.press(it) }, delete = { game.delete() }, submit = { game.submit(state) }, enabled = true)
    }
}

@Composable
private fun DuoClue(number: Int, word: DuoWord, found: Boolean, revealed: Boolean) {
    Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(22.dp), color = if (found) Palette.fill2 else Palette.fill1,
        border = androidx.compose.foundation.BorderStroke(1.dp, if (found) Palette.mint.copy(alpha = 0.5f) else Palette.line)) {
        Row(Modifier.padding(14.dp).semantics(mergeDescendants = true) {
            contentDescription = "Indice $number : ${word.hint}" + when { found -> ". Trouvé : ${word.word}"; revealed -> ". Réponse : ${word.word}"; else -> "" }
        }, verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(26.dp).background(if (found) Palette.mint else Palette.fill2, CircleShape), contentAlignment = Alignment.Center) {
                Text("$number", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = if (found) Palette.ink else Palette.secondary)
            }
            Column(Modifier.padding(start = 12.dp).weight(1f)) {
                Text(word.hint, style = Type.serifItalic(19))
                AnimatedContent(found || revealed, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "duo") { shown ->
                    if (shown) VowelReveal(word.word.uppercase(), found, Modifier.padding(top = 4.dp), maxSize = 26f, width = 230f)
                    else Text("à trouver", fontSize = 12.sp, color = Palette.tertiary, modifier = Modifier.padding(top = 4.dp))
                }
            }
        }
    }
}

@Composable
internal fun ColumnScope.Clue(card: Card) {
    val reduce = rememberReduceMotion()
    Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
        AnimatedContent(card, transitionSpec = {
            if (reduce) fadeIn() togetherWith fadeOut() else (fadeIn(tween(220)) + slideInVertically { it / 8 }) togetherWith fadeOut(tween(120))
        }, contentKey = { it.id }, label = "card") { shown ->
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                val consonants = shown.wordNoVowels
                Text(consonants, style = Type.serif(if (consonants.length > 9) 52 else if (consonants.length > 5) 64 else 84), letterSpacing = 3.sp, maxLines = 1,
                    modifier = Modifier.padding(top = 18.dp).semantics { contentDescription = "Consonnes : " + consonants.toList().joinToString(", ") })
                Text("${shown.category.label} · ${shown.difficulty.label}", fontSize = 12.sp, color = Palette.tertiary, modifier = Modifier.padding(top = 4.dp))
                Text("« ${shown.hint} »", style = Type.serifItalic(22), textAlign = TextAlign.Center, modifier = Modifier.padding(top = 14.dp, start = 10.dp, end = 10.dp))
            }
        }
    }
}

@Composable
private fun Controls(state: AppViewModel, game: ModeViewModel, skip: String, skipLabel: String) {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        AnswerLine(game.answer, game.mistakeTick, true)
        SkipChip(skip, skipLabel) { game.skip(state) }
    }
    LetterKeyboard(press = { game.press(it) }, delete = { game.delete() }, submit = { game.submit(state) }, enabled = !game.finished)
}

@Composable
internal fun SkipChip(text: String, label: String, action: () -> Unit) {
    val haptics = rememberHaptics()
    Box(Modifier.fillMaxWidth().padding(vertical = 8.dp), contentAlignment = Alignment.Center) {
        AssistChip({ haptics.selection(); action() }, { Text(text) }, Modifier.semantics { contentDescription = label }, shape = RoundedCornerShape(50),
            colors = AssistChipDefaults.assistChipColors(containerColor = Palette.fill1, labelColor = Palette.secondary))
    }
}

@Composable
private fun Stat(value: String, label: String, modifier: Modifier, highlight: Boolean = false) {
    Surface(modifier, shape = RoundedCornerShape(16.dp), color = Palette.fill1, border = androidx.compose.foundation.BorderStroke(1.dp, Palette.line)) {
        Column(Modifier.padding(vertical = 8.dp).semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally) {
            Text(value, fontSize = 18.sp, fontWeight = FontWeight.Bold, maxLines = 1, color = if (highlight) Palette.mint else Palette.foreground)
            Text(label, fontSize = 11.sp, color = Palette.tertiary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

// ---- Results

@Composable
private fun ModeResult(state: AppViewModel, game: ModeViewModel, replay: () -> Unit, close: () -> Unit) {
    val mode = game.mode
    val haptics = rememberHaptics()
    val reduce = rememberReduceMotion()
    val mainKey = mode.mainRecord
    val records = state.progress.records(mode)
    val celebrate = remember { Animatable(if (reduce) 1f else 0.85f) }
    LaunchedEffect(Unit) {
        if (game.improved(mainKey)) { haptics.success(); if (!reduce) { delay(250); celebrate.animateTo(1f, spring(dampingRatio = 0.5f, stiffness = 300f)) } }
    }
    val now = game.elapsedMs
    val (kicker, value, unit) = when (mode) {
        PlayMode.SPRINT -> { val found = game.sprint?.found ?: 0; Triple(if ((game.sprint?.remainingMs(now) ?: 0) == 0) "Temps écoulé !" else "Sprint arrêté", found, if (found > 1) "mots trouvés en 90 s" else "mot trouvé en 90 s") }
        PlayMode.SURVIVAL -> Triple(if ((game.survival?.lives ?: 0) == 0) "Plus de vies…" else "Partie terminée", game.survival?.level ?: 1, "niveau atteint")
        PlayMode.DUO -> { val solved = game.duo?.solved ?: 0; Triple(if (game.duo?.perfect == true) "Parfait, 10 sur 10 !" else "Partie terminée", solved, if (solved > 1) "paires trouvées" else "paire trouvée") }
    }
    val tiles: List<Pair<String, String>> = when (mode) {
        PlayMode.SPRINT -> game.sprint?.let { listOf("${it.bestCombo}" to "meilleur combo", "${it.accuracy} %" to "précision", "${it.skips}" to (if (it.skips > 1) "passés" else "passé")) }
        PlayMode.SURVIVAL -> game.survival?.let { listOf("${it.found}" to (if (it.found > 1) "mots trouvés" else "mot trouvé"), "${it.mistakes}" to (if (it.mistakes > 1) "erreurs" else "erreur"), Format.number(records.best(ModeStat.WORDS)) to "meilleur parcours") }
        PlayMode.DUO -> game.duo?.let { listOf(Format.clock(it.playMs(now)) to "temps", "${it.wordsFound}/${it.duos.size * 2}" to "réponses", "${it.errors}" to (if (it.errors > 1) "erreurs" else "erreur")) }
    } ?: emptyList()
    Surface(Modifier.fillMaxWidth().padding(horizontal = 8.dp).navigationBarsPadding().padding(bottom = 8.dp), shape = RoundedCornerShape(40.dp),
        color = Palette.surfaceHigh, border = androidx.compose.foundation.BorderStroke(1.dp, Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.3f), Palette.border)))) {
        Column(Modifier.padding(horizontal = 22.dp, vertical = 26.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(kicker, style = Type.serifItalic(24), color = Palette.secondary)
            Text(Format.number(value), fontSize = 60.sp, fontWeight = FontWeight.Black, letterSpacing = (-1.5).sp, modifier = Modifier.padding(top = 4.dp))
            Text(unit, fontSize = 13.sp, color = Palette.tertiary)
            Row(Modifier.padding(top = 18.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                tiles.forEach { (v, l) ->
                    Surface(Modifier.weight(1f), shape = RoundedCornerShape(20.dp), color = Palette.fill1) {
                        Column(Modifier.padding(vertical = 12.dp).semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(v, fontSize = 20.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                            Text(l, fontSize = 12.sp, color = Palette.tertiary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
            Box(Modifier.padding(top = 14.dp)) {
                when {
                    game.improved(mainKey) -> Row(Modifier.scale(celebrate.value), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.EmojiEvents, null, tint = Palette.mint)
                        Text("Nouveau record personnel", color = Palette.mint, fontWeight = FontWeight.Bold, fontSize = 15.sp, modifier = Modifier.padding(start = 6.dp))
                    }
                    mainKey in game.beaten -> Text("Premier record établi", color = Palette.secondary, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                    else -> Text("Record : " + recordText(mode, records.best(mainKey)),
                        color = Palette.secondary, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                }
            }
            val survival = game.survival
            if (mode == PlayMode.SURVIVAL && survival != null && survival.lives == 0) survival.card?.let {
                Text("Le dernier mot était « ${it.wordFull} ».", fontSize = 13.sp, color = Palette.tertiary, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
            }
            Row(Modifier.padding(top = 20.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                TonalButton("Accueil", Modifier.weight(1f), onClick = close)
                PrimaryButton("Rejouer", Modifier.weight(1f), onClick = replay)
            }
            Spacer(Modifier.height(10.dp))
            Text("Record personnel : il ne compte pas dans les classements du mot du jour.", fontSize = 11.sp, color = Palette.tertiary, textAlign = TextAlign.Center)
        }
    }
}

/** The record a mode is judged on: words in Sprint, the level in Survie, pairs then time in Double sens. */
internal val PlayMode.mainRecord: String get() = when (this) { PlayMode.SPRINT -> ModeStat.WORDS; PlayMode.SURVIVAL -> ModeStat.LEVEL; PlayMode.DUO -> ModeStat.DUO }

/** A mode's main record in words: "12 mots", "niveau 4", "4 paires en 1:32". */
internal fun recordText(mode: PlayMode, value: Int): String = when (mode) {
    PlayMode.SPRINT -> "${Format.number(value)} mot" + if (value > 1) "s" else ""
    PlayMode.SURVIVAL -> "niveau ${maxOf(1, value)}"
    PlayMode.DUO -> if (value <= 0) "aucun" else {
        val solved = DuoRecord.solved(value)
        "$solved paire" + (if (solved > 1) "s" else "") + " en " + Format.clock(DuoRecord.seconds(value) * 1000)
    }
}
