package com.poupoutch.cnsnn.ui

import androidx.compose.ui.draw.shadow
import androidx.compose.ui.zIndex
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.heightIn
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Backspace
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.layout
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.viewmodel.compose.viewModel
import com.poupoutch.cnsnn.core.Attempt
import com.poupoutch.cnsnn.core.Card
import com.poupoutch.cnsnn.core.CatchUp
import com.poupoutch.cnsnn.core.DailyScore
import com.poupoutch.cnsnn.core.Category
import com.poupoutch.cnsnn.core.DailyStanding
import com.poupoutch.cnsnn.core.Difficulty
import com.poupoutch.cnsnn.core.Format
import com.poupoutch.cnsnn.core.GameMode
import com.poupoutch.cnsnn.core.WordEngine
import com.poupoutch.cnsnn.data.CloudError
import com.poupoutch.cnsnn.share.Share
import com.poupoutch.cnsnn.state.AppViewModel
import com.poupoutch.cnsnn.state.GameViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.sin

@Composable
fun GameScreen(state: AppViewModel, mode: GameMode, category: Category?, difficulty: Difficulty?, catchUpDay: String? = null,
               tutorial: ((Boolean) -> Unit)? = null, close: () -> Unit) {
    val game: GameViewModel = viewModel()
    LaunchedEffect(Unit) { if (tutorial != null) game.loadTutorial(TUTORIAL_CARD) else game.loadOnce(mode, category, difficulty, state, catchUpDay) }
    // First-launch tutorial: this page with an example word (TR), explained step by step.
    val targets = remember { TutorialTargets() }
    val demo = remember { TutorialDemo() }
    Box(Modifier.fillMaxSize()) {
        CompositionLocalProvider(LocalTutorialTargets provides targets.takeIf { tutorial != null }, LocalTutorialDemo provides demo.takeIf { tutorial != null }) {
            GameContent(state, game, mode, close)
        }
        if (tutorial != null) TutorialGameOverlay(targets, demo, revealHint = { game.revealHint(state) }, finish = tutorial)
    }
}

@Composable
private fun GameContent(state: AppViewModel, game: GameViewModel, mode: GameMode, close: () -> Unit) {
    // The local clock stops while the app is in the background (the daily clock is the server's).
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_PAUSE) game.pause() else if (event == Lifecycle.Event.ON_RESUME) game.resume()
        }
        lifecycle.addObserver(observer); onDispose { lifecycle.removeObserver(observer) }
    }
    BackHandler(onBack = close)
    var confirmSkip by remember { mutableStateOf(false) }
    var reporting by remember { mutableStateOf(false) }
    val result = game.result
    // A found daily word: the 12h reminder is offered once back on the home page.
    LaunchedEffect(result?.id) { if (mode == GameMode.DAILY && game.catchUpDay == null && result?.correct == true && state.local.reminderOfferDue) state.reminderPending = true }

    Box(Modifier.fillMaxSize()) {
        AmbientBackground(dimmed = result == null)
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(horizontal = 12.dp)) {
            TopBar(state, game, mode, close) { reporting = true }
            when (val phase = game.phase) {
                GameViewModel.Phase.Loading -> Centered {
                    CircularProgressIndicator(color = Palette.secondary)
                    Text("Lancement du chrono officiel…", color = Palette.secondary, modifier = Modifier.padding(top = 16.dp))
                }
                is GameViewModel.Phase.Failed -> Centered {
                    Icon(Icons.Filled.WifiOff, null, Modifier.size(44.dp), tint = Palette.secondary)
                    Text("Mot du jour indisponible", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 16.dp))
                    Text(phase.message + " Le mot reste caché tant que le chrono officiel n’a pas démarré.", color = Palette.secondary,
                        textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp, start = 12.dp, end = 12.dp))
                    PrimaryButton("Réessayer", Modifier.padding(top = 24.dp)) { game.retry(state) }
                    TextButton(close, Modifier.padding(top = 4.dp)) { Text("Retour") }
                }
                GameViewModel.Phase.Playing -> {
                    val card = game.card
                    if (card != null) Board(state, game, card, mode) { confirmSkip = true }
                    else if (result == null) Centered {
                        Icon(Icons.Outlined.Inventory2, null, Modifier.size(44.dp), tint = Palette.secondary)
                        Text("Aucune carte", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 16.dp))
                        Text("Aucune carte disponible pour ces filtres. Revenez en arrière pour les modifier.", color = Palette.secondary,
                            textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
                        TonalButton("Retour", Modifier.padding(top = 20.dp), onClick = close)
                    }
                }
            }
        }
        AnimatedVisibility(result != null, enter = fadeIn(), exit = fadeOut()) {
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.42f)))
        }
        AnimatedVisibility(result != null, Modifier.align(Alignment.BottomCenter),
            enter = slideInVertically(spring(dampingRatio = 0.85f, stiffness = Spring.StiffnessMediumLow)) { it }, exit = slideOutVertically { it }) {
            result?.let {
                ResultSheet(state, it, game.card, mode, game.finishedHere && game.wrongAnswers == 0 && !game.usedHint, game.standing,
                    game.pendingOfficial, game.ranked, game.usedHint, game.wrongAnswers, game.officialMs(it), catchUp = game.catchUpDay != null,
                    next = { game.next(state) }, close = close)
            }
        }
    }

    if (confirmSkip) AlertDialog({ confirmSkip = false },
        confirmButton = { TextButton({ confirmSkip = false; game.giveUp(state) }) { Text("Révéler le mot", color = Palette.red) } },
        dismissButton = { TextButton({ confirmSkip = false }) { Text("Continuer") } },
        title = { Text("Révéler le mot et terminer cette carte ?") })
    if (reporting) ReportDialog(state, game.card) { reporting = false }
}

@Composable
private fun Centered(content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxSize().padding(horizontal = 24.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally, content = content)
}

@Composable
private fun TopBar(state: AppViewModel, game: GameViewModel, mode: GameMode, close: () -> Unit, report: () -> Unit) {
    Box(Modifier.fillMaxWidth().height(56.dp)) {
        IconButton(close, Modifier.align(Alignment.CenterStart)) { Icon(Icons.Filled.Close, "Fermer") }
        Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(game.catchUpDay?.let { "Mot du " + Format.weekday(it) } ?: if (mode == GameMode.DAILY) "Mot du jour" else "Classique", fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
            game.card?.let { Text(it.difficulty.label, fontSize = 12.sp, color = Palette.tertiary) }
        }
        Row(Modifier.align(Alignment.CenterEnd), verticalAlignment = Alignment.CenterVertically) {
            val card = game.card
            if (card != null && game.result == null && listOf("seed-", "daily-", "secret-").none { card.id.startsWith(it) } && state.uid != null) {
                IconButton(report) { Icon(Icons.Outlined.Flag, "Signaler cette carte", tint = Palette.secondary) }
            }
            var tick by remember { mutableIntStateOf(0) }
            LaunchedEffect(Unit) { while (true) { delay(500); tick++ } }
            val ms = game.result?.timeMs ?: if (game.phase == GameViewModel.Phase.Playing) game.elapsedMs.also { tick } else 0
            Surface(shape = RoundedCornerShape(50), color = Palette.fill1, modifier = Modifier.padding(end = 4.dp).tutorialTarget(TutorialTarget.CLOCK)) {
                Text(Format.clock(ms), fontWeight = FontWeight.Bold, fontSize = 14.sp, modifier = Modifier.padding(horizontal = 13.dp, vertical = 8.dp)
                    .semantics { contentDescription = "Chrono " + Format.clock(ms) })
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun androidx.compose.foundation.layout.ColumnScope.Board(state: AppViewModel, game: GameViewModel, card: Card, mode: GameMode, skip: () -> Unit) {
    val haptics = rememberHaptics()
    val consonants = card.wordNoVowels
    // The clue area scrolls on its own: the answer, the buttons and the keyboard always stay in view.
    Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
        Column(Modifier.tutorialTarget(TutorialTarget.BOARD), horizontalAlignment = Alignment.CenterHorizontally) {
            val demo = LocalTutorialDemo.current
            if (demo != null) {
                // The tutorial's example: the vowels slide in and out of TR.
                Box(Modifier.padding(top = 28.dp).heightIn(min = 96.dp), contentAlignment = Alignment.Center) {
                    androidx.compose.runtime.key(demo.step, demo.hintShown) { MorphWord(demo.word, demo.from, 80) }
                }
            } else {
                Text(consonants, style = Type.serif(if (consonants.length > 9) 52 else if (consonants.length > 5) 64 else 88), letterSpacing = 3.sp, maxLines = 1,
                    modifier = Modifier.padding(top = 28.dp).semantics { contentDescription = "Consonnes : " + WordEngine.spoken(consonants) })
            }
            Box(Modifier.padding(top = 18.dp).width(36.dp)) { Divider() }
            AnimatedVisibility(game.usedHint, enter = fadeIn() + slideInVertically { it / 3 }) {
                Text("« ${card.hint} »", style = Type.serifItalic(24), textAlign = TextAlign.Center, modifier = Modifier.padding(top = 18.dp, start = 10.dp, end = 10.dp))
            }
        }
        FlowRow(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            game.wrongGuesses.forEach { guess ->
                Text(WordEngine.normalize(guess), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.6.sp, color = Palette.red,
                    textDecoration = TextDecoration.LineThrough,
                    modifier = Modifier.background(Palette.redSoft, RoundedCornerShape(50)).padding(horizontal = 10.dp, vertical = 4.dp))
            }
        }
        // The theme, near the consonants where the eyes are (the difficulty stays under the title).
        Text("Thème : " + card.category.label, fontSize = 12.sp, color = Palette.tertiary, maxLines = 1, textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 6.dp).tutorialTarget(TutorialTarget.TITLE))
        if (mode == GameMode.DAILY && game.result == null) {
            val line = when {
                game.checking -> "Vérification…"
                game.notice != null -> game.notice!!
                game.catchUpDay != null -> "Rattrapage : compte dans la semaine avec 5 min en plus."
                else -> null
            }
            if (line != null) Text(line, fontSize = 12.sp, color = if (game.notice != null) Palette.secondary else Palette.tertiary, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 6.dp))
            AnimatedVisibility(game.remainingText != null, enter = fadeIn() + slideInVertically { it / 2 }, exit = fadeOut()) {
                Text(game.remainingText ?: "", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Palette.accent, textAlign = TextAlign.Center,
                    modifier = Modifier.padding(top = 6.dp).background(Palette.accent.copy(alpha = 0.14f), RoundedCornerShape(50)).padding(horizontal = 12.dp, vertical = 4.dp))
            }
        }
    }
    // After a minute on the Mot du jour without the hint, a small bubble points at Indice.
    var hintNudge by remember(card.id) { mutableStateOf(false) }
    if (mode == GameMode.DAILY && LocalTutorialDemo.current == null) LaunchedEffect(card.id) {
        while (!game.usedHint && game.result == null) {
            if (game.elapsedMs >= 60_000) { hintNudge = true; break }
            delay(1_000)
        }
    }
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        AnswerLine(game)
        AnimatedVisibility(hintNudge && !game.usedHint && game.result == null, enter = fadeIn() + slideInVertically { it / 2 }, exit = fadeOut()) {
            HintNudge()
        }
        Row(Modifier.padding(vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            AssistChip({ haptics.selection(); game.revealHint(state) }, {
                // The hint costs a minute on the Mot du jour only; in Classique it is free.
                Text(buildString { append("Indice"); if (game.usedHint) append("  révélé") else if (game.ranked) append("  +1 min") })
            }, Modifier.tutorialTarget(TutorialTarget.HINT), enabled = !game.usedHint && game.result == null && !game.checking, shape = RoundedCornerShape(50),
                colors = AssistChipDefaults.assistChipColors(containerColor = Palette.fill1))
            AssistChip(skip, { Text("Passer") }, enabled = game.result == null && !game.checking, shape = RoundedCornerShape(50),
                colors = AssistChipDefaults.assistChipColors(containerColor = Palette.fill1, labelColor = Palette.secondary))
        }
    }
    LetterKeyboard(press = { game.press(it) }, delete = { game.delete() }, submit = { game.submit(state) }, enabled = game.result == null && !game.checking)
    // Wrong guesses may be answered by the server a moment later: the buzz follows the shake.
    LaunchedEffect(game.mistakeTick) { if (game.mistakeTick > 0) haptics.retry() }
    LaunchedEffect(game.result?.id) { if (game.result?.correct == true) haptics.success() }
}

@Composable
private fun AnswerLine(game: GameViewModel) = AnswerLine(game.answer, game.mistakeTick, game.result == null)

/** The typed answer, gold vowels, a caret, and a shake on each wrong guess. */
@Composable
fun AnswerLine(answer: String, mistakeTick: Int, active: Boolean) {
    val shake = remember { Animatable(0f) }
    LaunchedEffect(mistakeTick) {
        if (mistakeTick > 0) { shake.snapTo(0f); shake.animateTo(1f, tween(420)) }
    }
    val dx = (10 * sin(shake.value * PI * 4) * (1 - shake.value)).toFloat()
    Row(Modifier.fillMaxWidth().height(58.dp).padding(horizontal = 24.dp).offset(x = dx.dp)
        .drawBehind { drawLine(Palette.tertiary, androidx.compose.ui.geometry.Offset(0f, size.height), androidx.compose.ui.geometry.Offset(size.width, size.height), 2f) }
        .semantics { contentDescription = "Votre réponse : " + answer.ifEmpty { "vide" } },
        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
        if (answer.isEmpty()) Text("votre réponse", style = Type.serifItalic(22), color = Palette.tertiary)
        else Text(highlighted(answer), fontSize = if (answer.length > 14) 22.sp else 30.sp, fontWeight = FontWeight.Medium, letterSpacing = 2.sp, maxLines = 1)
        if (active) Caret()
    }
}

@Composable
private fun Caret() {
    var visible by remember { mutableStateOf(true) }
    LaunchedEffect(Unit) { while (true) { delay(530); visible = !visible } }
    Box(Modifier.padding(start = 2.dp).width(2.5.dp).height(30.dp).alpha(if (visible) 1f else 0f).background(Palette.foreground, RoundedCornerShape(2.dp)))
}

/**
 * AZERTY keyboard laid out like the phone's French one (Gboard, iPhone): same rows and key sizes, ⌫ at the
 * right end of the third row, a wide space bar with Valider where Enter goes, no dead zone between keys (a
 * touch in a gap goes to the nearest key) and the letter popping up above the finger. Vowels in gold.
 */
@Composable
fun LetterKeyboard(press: (String) -> Unit, delete: () -> Unit, submit: () -> Unit, enabled: Boolean) {
    val haptics = rememberHaptics()
    val rows = listOf("AZERTYUIOP", "QSDFGHJKLM", "WXCVBN")
    val rowHeight = 56.dp
    // A background, not a Surface: a Surface clips, and the top row's popups go past the edge.
    Box(Modifier.bleed(9.dp).fillMaxWidth().padding(bottom = 6.dp).background(Palette.surface.copy(alpha = 0.9f), RoundedCornerShape(28.dp))) {
        BoxWithConstraints(Modifier.padding(horizontal = 3.dp, vertical = 6.dp)) {
            val unit = maxWidth / 10
            Column {
                rows.take(2).forEach { row ->
                    Row(Modifier.fillMaxWidth()) {
                        row.forEach { letter -> Key(letter.toString(), isVowel(letter), unit, rowHeight, enabled) { haptics.key(); press(letter.toString()) } }
                    }
                }
                Row(Modifier.fillMaxWidth()) {
                    // Where the phone has ⇧: left empty, so W to N sit where the thumb expects them.
                    Spacer(Modifier.width(unit * 1.6f))
                    rows[2].forEach { letter -> Key(letter.toString(), isVowel(letter), unit, rowHeight, enabled) { haptics.key(); press(letter.toString()) } }
                    Spacer(Modifier.weight(1f))
                    Key("⌫", false, unit * 1.35f, rowHeight, enabled, label = "Effacer") { haptics.key(); delete() }
                }
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    // Space for answers in several words (Les Aristochats); spaces are ignored when checking.
                    Key("espace", false, unit * 7, rowHeight, enabled, label = "Espace") { haptics.key(); press(" ") }
                    androidx.compose.material3.Button({ haptics.selection(); submit() }, Modifier.weight(1f).padding(horizontal = 3.dp).height(rowHeight - 10.dp),
                        enabled = enabled, shape = RoundedCornerShape(24.dp),
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 4.dp)) { Text("Valider", fontWeight = FontWeight.Bold, fontSize = 16.sp, maxLines = 1) }
                }
            }
        }
    }
}

/** Widens past the screen's 12 dp margin (padding can't be negative): the keyboard runs edge to edge like the phone's. */
private fun Modifier.bleed(x: Dp) = layout { measurable, constraints ->
    val extra = x.roundToPx() * 2
    val placeable = measurable.measure(constraints.copy(minWidth = constraints.minWidth + extra, maxWidth = constraints.maxWidth + extra))
    layout(placeable.width - extra, placeable.height) { placeable.place(-extra / 2, 0) }
}

/** One key: the whole cell takes the touch, the cap sits inside it with the phone's gaps around. */
@Composable
private fun Key(text: String, vowel: Boolean, width: Dp, height: Dp, enabled: Boolean, label: String? = null, action: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val shape = RoundedCornerShape(8.dp)
    val letter = text.length == 1 && text != "⌫"
    val face: Modifier = if (vowel) Modifier.background(Brush.verticalGradient(listOf(Palette.accentTop, Palette.accentBottom)), shape)
        else Modifier.background(if (pressed && !letter) Palette.fill2 else Palette.fill1, shape).border(1.dp, Palette.border, shape)
    Box(Modifier.width(width).height(height)
        .clickable(interaction, indication = null, enabled = enabled, onClickLabel = label ?: text, onClick = action)
        .semantics { contentDescription = label ?: text }) {
        Box(Modifier.fillMaxSize().padding(horizontal = 3.dp, vertical = 5.dp).then(face), contentAlignment = Alignment.Center) {
            if (text == "⌫") Icon(Icons.AutoMirrored.Filled.Backspace, null, Modifier.size(20.dp), tint = Palette.foreground)
            else Text(text, fontSize = if (text.length > 1) 15.sp else 24.sp, color = if (vowel) Palette.onAccent else Palette.foreground)
        }
        // The letter pops up above the finger, as on the phone's keyboard.
        if (letter && pressed) {
            Box(Modifier.align(Alignment.BottomCenter).offset(y = -height + 2.dp).width(width + 4.dp).height(56.dp).zIndex(1f)
                .shadow(6.dp, shape)
                .then(if (vowel) Modifier.background(Brush.verticalGradient(listOf(Palette.accentTop, Palette.accentBottom)), shape)
                      else Modifier.background(Palette.surface, shape).border(1.dp, Palette.border, shape)),
                contentAlignment = Alignment.Center) {
                Text(text, fontSize = 32.sp, color = if (vowel) Palette.onAccent else Palette.foreground)
            }
        }
    }
}

// ---- Result

@Composable
private fun ResultSheet(state: AppViewModel, result: Attempt, card: Card?, mode: GameMode, firstTry: Boolean, standing: DailyStanding?,
                        pending: Boolean, ranked: Boolean, usedHint: Boolean, wrongAnswers: Int, officialMs: Int, catchUp: Boolean, next: () -> Unit, close: () -> Unit) {
    val context = LocalContext.current
    Surface(Modifier.fillMaxWidth().padding(horizontal = 8.dp).navigationBarsPadding().padding(bottom = 8.dp), shape = RoundedCornerShape(40.dp),
        color = Palette.surfaceHigh, border = androidx.compose.foundation.BorderStroke(1.dp, Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.3f), Palette.border)))) {
        Column(Modifier.padding(horizontal = 22.dp, vertical = 26.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(when { !result.correct -> "Pas cette fois…"; firstTry -> "Du premier coup, sans indice."; else -> "Trouvé en ${Format.clock(result.timeMs)}." },
                style = Type.serifItalic(24), color = if (result.correct) Palette.mint else Palette.red)
            if (card != null) {
                VowelReveal(card.wordFull.uppercase(), result.correct, Modifier.padding(top = 10.dp))
                Text("« ${card.hint} »", color = Palette.secondary, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 6.dp))
            }
            Row(Modifier.padding(top = 18.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (catchUp) {
                    // Counted: the real time, the hint minute, then 5 minutes more.
                    ResultTile(Format.clock(DailyScore.catchUpScoreMs(result.timeMs, usedHint, result.correct)), "compté", Modifier.weight(1f))
                    ResultTile(if (usedHint) "+1 min" else "non", "indice", Modifier.weight(1f))
                    ResultTile("${CatchUp.toPlay(state.catchUpDays())}", "à rattraper", Modifier.weight(1f))
                } else if (mode == GameMode.DAILY) {
                    // The official time: the hint adds a minute, a lost day counts ten.
                    ResultTile(Format.clock(officialMs), when { !result.correct -> "compté"; usedHint -> "avec indice"; else -> "temps" }, Modifier.weight(1f))
                    ResultTile("$wrongAnswers", if (wrongAnswers > 1) "erreurs" else "erreur", Modifier.weight(1f))
                    ResultTile("${state.streak}", "jours de série", Modifier.weight(1f))
                } else {
                    ResultTile(Format.clock(result.timeMs), "temps", Modifier.weight(1f))
                    ResultTile(Format.number(state.progress.correctAnswers), "mots trouvés", Modifier.weight(1f))
                    ResultTile("${state.progress.level}", "niveau", Modifier.weight(1f))
                }
            }
            if (catchUp) { if (pending) OfficialLine(result, null, true) }
            else if (mode == GameMode.DAILY && ranked) OfficialLine(result, standing, pending)
            else if (!catchUp && result.correct && result.timeMs == state.progress.bestTimeMs)
                Text("🏆 Votre meilleur temps", color = Palette.mint, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 12.dp))
            if (mode == GameMode.DAILY && !catchUp && state.uid != null) Box(Modifier.padding(top = 18.dp)) {
                ChallengePrompt(result.correct) { state.challengeRequest++; close() }
            }
            Row(Modifier.padding(top = 20.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (!catchUp) FilledTonalButton({ Share.result(context, result, card, mode) }, Modifier.height(56.dp), shape = RoundedCornerShape(28.dp)) {
                    Icon(Icons.Filled.Share, null, Modifier.size(18.dp)); Text("Partager", Modifier.padding(start = 8.dp))
                }
                val ends = mode == GameMode.DAILY
                PrimaryButton(if (ends) "Terminer" else "Mot suivant", Modifier.weight(1f)) {
                    // Today's word: straight to the day's ranking.
                    if (ends && ranked && !catchUp) state.leaderboardRequest++
                    if (ends) close() else next()
                }
            }
            if (catchUp) Text(when {
                    pending -> "Votre partie est gardée sur ce téléphone et sera validée au retour du réseau."
                    result.correct -> "Mot rattrapé : il compte au classement avec 5 min en plus."
                    else -> "Ce jour compte comme joué, sans mot trouvé."
                },
                style = MaterialTheme.typography.bodySmall, color = Palette.tertiary, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 14.dp))
            else if (mode == GameMode.CLASSIC) TextButton(close, Modifier.padding(top = 6.dp)) { Text("Retour à l’accueil", color = Palette.secondary) }
            else Text(if (pending) "Votre partie est gardée sur ce téléphone et sera validée au retour du réseau." else "Votre défi du jour est enregistré. À demain !",
                style = MaterialTheme.typography.bodySmall, color = Palette.tertiary, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 14.dp))
        }
    }
}

@Composable
private fun OfficialLine(result: Attempt, standing: DailyStanding?, pending: Boolean) {
    Column(Modifier.padding(top = 12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        val rank = standing?.rank
        when {
            pending -> Text("Validation du temps officiel…", color = Palette.secondary, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
            standing != null && result.correct && rank != null -> {
                if (rank == 1) Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.EmojiEvents, null, tint = Palette.mint)
                    Text("Vous êtes le numéro 1 !", color = Palette.mint, fontWeight = FontWeight.Bold, fontSize = 17.sp, modifier = Modifier.padding(start = 6.dp))
                } else standing.topPercent?.let { Text("Top $it %", color = Palette.mint, fontWeight = FontWeight.Bold, fontSize = 17.sp) }
                Text(Format.ordinal(rank) + " sur ${standing.players} aujourd’hui", color = Palette.secondary, fontSize = 13.sp)
            }
            standing != null && !result.correct && standing.tried > 1 ->
                Text("${standing.tried} joueurs ont tenté ce mot aujourd’hui", color = Palette.secondary, fontSize = 13.sp)
        }
    }
}

@Composable
private fun ResultTile(value: String, label: String, modifier: Modifier) {
    Surface(modifier, shape = RoundedCornerShape(20.dp), color = Palette.fill1) {
        Column(Modifier.padding(vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(value, fontSize = 22.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            Text(label, fontSize = 12.sp, color = Palette.tertiary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** The signature moment: consonants stay, the vowels slide into the gaps one by one, then the word glows. */
@Composable
fun VowelReveal(word: String, correct: Boolean, modifier: Modifier = Modifier, maxSize: Float = 42f, width: Float = 318f) {
    val reduce = rememberReduceMotion()
    val haptics = rememberHaptics()
    val vowelCount = word.count { isVowel(it) }
    val progress = remember(word) { List(vowelCount) { Animatable(if (reduce) 1f else 0f) } }
    val glow = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(word) {
        if (reduce) return@LaunchedEffect
        progress.forEachIndexed { index, anim ->
            delay(if (index == 0) 350 else 160)
            scope.launch { anim.animateTo(1f, if (correct) spring(dampingRatio = 0.62f, stiffness = 300f) else tween(500)) }
            if (correct) haptics.key()
        }
        if (correct && vowelCount > 0) { delay(300); glow.animateTo(1f, tween(350)); delay(500); glow.animateTo(0f, tween(900)) }
    }
    val size = minOf(maxSize, width / (maxOf(word.length, 1) * 0.8f))
    Row(modifier.widthIn(max = 360.dp).drawBehind {
        if (glow.value > 0) drawCircle(Brush.radialGradient(listOf(Palette.accent.copy(alpha = 0.45f * glow.value), Color.Transparent), radius = this.size.width / 1.6f),
            radius = this.size.width / 1.6f)
    }.semantics { contentDescription = word }) {
        var order = 0
        word.forEach { c ->
            if (isVowel(c)) {
                val p = progress[order++].value
                Text(c.toString(), fontSize = size.sp, fontWeight = FontWeight.Black, color = if (correct) Palette.accent else Palette.secondary,
                    modifier = Modifier.collapse(p).alpha(p.coerceIn(0f, 1f)), softWrap = false)
            } else Text(c.toString(), fontSize = size.sp, fontWeight = FontWeight.Black, color = Palette.foreground, softWrap = false)
        }
    }
}

@Composable
private fun ReportDialog(state: AppViewModel, card: Card?, dismiss: () -> Unit) {
    var reason by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    AlertDialog(dismiss, title = { Text("Signaler la carte") },
        text = { OutlinedTextField(reason, { reason = it.take(300) }, label = { Text("Pourquoi ? (5 à 300 caractères)") }) },
        confirmButton = {
            TextButton({
                val id = card?.id ?: return@TextButton
                scope.launch {
                    try { state.cloud.report(id, reason.trim()); android.widget.Toast.makeText(context, "Signalement envoyé", android.widget.Toast.LENGTH_SHORT).show() }
                    catch (e: Exception) { state.error = CloudError.message(e) }
                }
                dismiss()
            }, enabled = reason.trim().length in 5..300) { Text("Envoyer") }
        },
        dismissButton = { TextButton(dismiss) { Text("Annuler") } })
}

/** "Besoin d’un indice ?": a light bubble whose arrow points down at the Indice button. */
@Composable
private fun HintNudge() {
    Column(Modifier.padding(top = 6.dp).semantics(mergeDescendants = true) { contentDescription = "Besoin d’un indice ? Le bouton Indice est juste en dessous." },
        horizontalAlignment = Alignment.CenterHorizontally) {
        Surface(shape = RoundedCornerShape(50), color = Palette.foreground, shadowElevation = 6.dp) {
            Text("Besoin d’un indice ?", color = Palette.ink, fontWeight = FontWeight.SemiBold, fontSize = 14.sp,
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp))
        }
        val color = Palette.foreground
        androidx.compose.foundation.Canvas(Modifier.width(16.dp).height(8.dp)) {
            drawPath(androidx.compose.ui.graphics.Path().apply { moveTo(0f, 0f); lineTo(size.width / 2, size.height); lineTo(size.width, 0f); close() }, color)
        }
    }
}
