package com.poupoutch.cnsnn.ui

import androidx.activity.compose.BackHandler
import kotlinx.coroutines.delay
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.draw.alpha
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.animateValueAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt

/** The places on the home page the first-launch tutorial points at. */
enum class TutorialTarget { DAILY, PLAY }

/** Where the targets are on screen, filled by the home page and read by the overlay. */
class TutorialTargets { val rects = mutableStateMapOf<TutorialTarget, Rect>() }

val LocalTutorialTargets = staticCompositionLocalOf<TutorialTargets?> { null }

fun Modifier.tutorialTarget(target: TutorialTarget): Modifier = composed {
    val targets = LocalTutorialTargets.current ?: return@composed this
    // A target that leaves the screen (the daily word found) is forgotten, so nothing points at an old place.
    DisposableEffect(targets) { onDispose { targets.rects.remove(target) } }
    onGloballyPositioned { targets.rects[target] = it.boundsInRoot() }
}

/** A fixed example, never the real daily word, so the tutorial cannot give anything away. */
private const val EXAMPLE = "TR"
private const val THEME = "Général · Facile"

private enum class TutorialStep(val target: TutorialTarget?, val title: String, val message: String, val word: String? = null) {
    PLAY(TutorialTarget.DAILY, "Le mot du jour",
        "Un nouveau mot chaque jour, le même pour tous. Appuyez sur Jouer pour lancer la partie !"),
    CONSONANTS(null, "J’ai enlevé les voyelles",
        "Il ne reste que les consonnes de ce mot, dans l’ordre. À vous de retrouver le mot !"),
    FIRST(null, "Ça peut être TROU…", "Les voyelles O et U reviennent se glisser entre T et R.", "TROU"),
    SECOND(null, "… ou AUTEUR…",
        "On repart de TR : cette fois, des voyelles se glissent aussi avant le T. Plusieurs mots sont possibles !", "AUTEUR"),
    HELP(null, "Si vous ne trouvez pas…",
        "… prenez un indice ! Appuyez sur Indice (+1 min sur le mot du jour). En haut, le thème du mot et le chrono, qui part dès que vous appuyez sur Jouer."),
}

/**
 * First-launch tutorial: dims the app around the daily card with its Jouer button pulsing, then an
 * example (TR: TROU, but also AUTEUR) and where the theme, the hint and the clock are.
 */
@Composable
fun TutorialOverlay(targets: TutorialTargets, finish: () -> Unit) {
    var index by rememberSaveable { mutableStateOf(0) }
    val step = TutorialStep.entries[index]
    // The last step: Indice was tapped, the hint is showing and AUTEUR slides in.
    var hintShown by rememberSaveable(index) { mutableStateOf(false) }
    val haptics = rememberHaptics()
    fun next() { haptics.selection(); if (index == TutorialStep.entries.lastIndex) finish() else index++ }
    fun back() { haptics.selection(); if (index > 0) index-- }
    BackHandler { if (index > 0) back() else finish() }

    val density = LocalDensity.current
    var origin by remember { mutableStateOf(Offset.Zero) }
    var bounds by remember { mutableStateOf(Rect.Zero) }
    val target = step.target?.let { targets.rects[it] }?.translate(-origin)
    val hole = target?.inflate(with(density) { 6.dp.toPx() }) ?: Rect(bounds.center, bounds.center)
    // The Jouer button, ringed in gold on the first step.
    val play = if (step == TutorialStep.PLAY) targets.rects[TutorialTarget.PLAY]?.translate(-origin)?.inflate(with(density) { 6.dp.toPx() }) else null
    val reduce = rememberReduceMotion()
    val animatedHole by animateValueAsState(hole, Rect.VectorConverter, if (reduce) tween(0) else tween(420), label = "hole")
    val radius by animateFloatAsState(if (step.target == null) 0f else with(density) { 34.dp.toPx() }, if (reduce) tween(0) else tween(420), label = "radius")
    val pulse by rememberInfiniteTransition(label = "pulse").animateFloat(1f, if (reduce) 1f else 0.35f,
        infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "pulse")

    Box(Modifier.fillMaxSize()
        .onGloballyPositioned { origin = it.positionInRoot(); bounds = Rect(Offset.Zero, Offset(it.size.width.toFloat(), it.size.height.toFloat())) }
        // The app underneath stays out of reach while the tutorial is up.
        .pointerInput(Unit) { detectTapGestures {} }
        .testTag("tutorial")) {
        Canvas(Modifier.fillMaxSize()) {
            val path = Path().apply {
                fillType = PathFillType.EvenOdd
                addRect(Rect(Offset.Zero, this@Canvas.size))
                if (animatedHole.width > 1f) addRoundRect(RoundRect(animatedHole, CornerRadius(radius)))
            }
            drawPath(path, Color.Black.copy(alpha = 0.76f))
            if (play != null) {
                drawRoundRect(Palette.accent.copy(alpha = pulse), play.topLeft, play.size, CornerRadius(play.height / 2), style = Stroke(2.5.dp.toPx()))
            }
        }
        // The lit Jouer button can be tapped to go on, like the real one.
        if (play != null) {
            with(density) {
                Box(Modifier.offset { IntOffset(play.left.roundToInt(), play.top.roundToInt()) }.size(play.width.toDp(), play.height.toDp())
                    .clickable(role = Role.Button) { next() }
                    .semantics { contentDescription = "Jouer" }
                    .testTag("tutorial.play"))
            }
        }
        TextButton(finish, Modifier.align(Alignment.TopEnd).statusBarsPadding().padding(end = 8.dp).testTag("tutorial.skip")) {
            Text("Passer", color = Palette.secondary, fontWeight = FontWeight.SemiBold)
        }
        if (step.target != null && target != null) {
            val top = with(density) { (hole.bottom + 18.dp.toPx()).roundToInt() }
            Box(Modifier.fillMaxWidth().offset { IntOffset(0, top) }.padding(horizontal = 20.dp), contentAlignment = Alignment.TopCenter) {
                Callout(step, index, false, ::next, ::back)
            }
        } else {
            Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(horizontal = 26.dp, vertical = 48.dp),
                verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                Example(step, hintShown) { haptics.selection(); hintShown = true }
                Spacer(Modifier.height(18.dp))
                Callout(step, index, hintShown, ::next, ::back)
            }
        }
    }
}

@Composable
private fun Callout(step: TutorialStep, index: Int, hintShown: Boolean, next: () -> Unit, back: () -> Unit) {
    AnimatedContent(step, Modifier.widthIn(max = 560.dp), transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "callout") { shown ->
        SectionCard(radius = 28.dp) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.semantics {
                contentDescription = "Étape ${shown.ordinal + 1} sur ${TutorialStep.entries.size}"
            }) {
                TutorialStep.entries.forEach { item ->
                    Box(Modifier.height(6.dp).width(if (item == shown) 18.dp else 6.dp)
                        .background(if (item == shown) Palette.accent else Palette.fill2, RoundedCornerShape(3.dp)))
                }
            }
            Text(shown.title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(top = 14.dp).semantics { heading() })
            Text(if (shown == TutorialStep.HELP && hintShown) "« Il a écrit le livre. » : c’est AUTEUR ! Le thème et le chrono sont en haut, comme ici." else shown.message,
                color = Palette.secondary, modifier = Modifier.padding(top = 6.dp))
            Row(Modifier.fillMaxWidth().padding(top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                if (index > 0) TextButton(back) { Text("Retour", color = Palette.secondary, fontWeight = FontWeight.SemiBold) }
                Spacer(Modifier.weight(1f))
                // The button breathes, so it is clear a tap goes on.
                val reduce = rememberReduceMotion()
                val breath by rememberInfiniteTransition(label = "next").animateFloat(1f, if (reduce) 1f else 1.06f,
                    infiniteRepeatable(tween(800), RepeatMode.Reverse), label = "next")
                Button(next, Modifier.heightIn(min = 48.dp).graphicsLayer { scaleX = breath; scaleY = breath }, shape = RoundedCornerShape(24.dp)) {
                    Text(if (shown == TutorialStep.HELP) "À vous de jouer" else "Suivant", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                }
            }
        }
    }
}

/**
 * A small game screen: the title with the theme and the difficulty, the clock at the top right, the word,
 * then the Indice button. TR alone, then the vowels slide into it: TROU, back to TR, then AUTEUR (tap the
 * word to see it again). On the last step the theme, the clock and the hint get a gold ring.
 */
@Composable
private fun Example(step: TutorialStep, hintShown: Boolean, showHint: () -> Unit) {
    val help = step == TutorialStep.HELP
    val hint = help && hintShown
    val pulse by rememberInfiniteTransition(label = "lit").animateFloat(1f, if (rememberReduceMotion()) 1f else 0.25f,
        infiniteRepeatable(tween(700), RepeatMode.Reverse), label = "lit")
    // Steady around the theme and the clock; Indice blinks until it is tapped.
    val ring = Modifier.border(2.dp, Palette.accent.copy(alpha = if (help) 1f else 0f), RoundedCornerShape(50))
    val blinking = help && !hint
    SectionCard(Modifier.widthIn(max = 560.dp), padding = 18.dp, radius = 30.dp) {
        Box(Modifier.fillMaxWidth()) {
            Column(Modifier.align(Alignment.Center).then(ring).padding(horizontal = 14.dp, vertical = 6.dp)
                .semantics(mergeDescendants = true) { contentDescription = "Exemple, thème : $THEME" },
                horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Exemple", fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                Text(THEME, fontSize = 12.sp, fontWeight = if (help) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (help) Palette.accent else Palette.tertiary)
            }
            ExampleClock(help, Modifier.align(Alignment.CenterEnd).then(ring))
        }
        Box(Modifier.fillMaxWidth().heightIn(min = 96.dp).padding(top = 8.dp), contentAlignment = Alignment.Center) {
            // The last step starts again from TR; the hint brings AUTEUR in.
            key(step, hint) {
                MorphWord(if (hint) "AUTEUR" else step.word, if (step == TutorialStep.SECOND) TutorialStep.FIRST.word else null)
            }
        }
        if (hint) Text("« Il a écrit le livre. »", style = Type.serifItalic(20), textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth())
        Row(Modifier.align(Alignment.CenterHorizontally).padding(top = 12.dp)
            .border(2.dp, Palette.accent.copy(alpha = if (blinking) pulse else 0f), RoundedCornerShape(50))
            .background(if (blinking) Palette.accent.copy(alpha = 0.18f * pulse) else Palette.fill1, RoundedCornerShape(50))
            .clickable(enabled = blinking, role = Role.Button, onClick = showHint)
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .testTag("tutorial.hint"),
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Indice", fontWeight = FontWeight.Bold, fontSize = 13.sp)
            Text(if (hint) "révélé" else "+1 min", fontSize = 13.sp)
        }
    }
}

/** The example's clock, like the game's: it runs on the last step, from 0:00. */
@Composable
private fun ExampleClock(running: Boolean, modifier: Modifier) {
    var seconds by remember { mutableStateOf(0) }
    LaunchedEffect(running) { seconds = 0; while (running) { delay(1_000); seconds++ } }
    Text("%d:%02d".format(seconds / 60, seconds % 60), fontWeight = FontWeight.Bold, fontSize = 14.sp,
        modifier = modifier.background(Palette.fill1, RoundedCornerShape(50)).padding(horizontal = 13.dp, vertical = 8.dp)
            .semantics { contentDescription = "Chrono" })
}

private const val OUT = 0.45f
private const val PAUSE = 0.4f
private const val LEAD = 0.35f
private const val GROW = 0.45f
private const val STAGGER = 0.1f

/**
 * The example word, one big serif line: the consonants stay put and the gold vowels slide in between
 * them. With `from`, that word's vowels first slide back out, so TROU turns back into TR before AUTEUR.
 */
@Composable
private fun MorphWord(word: String?, from: String?) {
    val reduce = rememberReduceMotion()
    val clock = remember { Animatable(0f) }
    var replays by remember { mutableStateOf(0) }
    LaunchedEffect(replays) {
        if (reduce) return@LaunchedEffect
        clock.snapTo(0f)
        clock.animateTo(4f, tween(4_000, easing = LinearEasing))
    }
    val time = clock.value
    val back = if (from == null) 0f else OUT + PAUSE
    val collapsing = from != null && !reduce && time < back
    val shown = if (collapsing) from!! else word ?: EXAMPLE
    fun progress(index: Int): Float = when {
        reduce -> 1f
        collapsing -> 1f - ease(time / OUT)
        else -> ease((time - back - LEAD - index * STAGGER) / GROW)
    }
    Row(Modifier.pointerInput(Unit) { detectTapGestures { replays++ } }
        .semantics(mergeDescendants = true) { contentDescription = word ?: "Consonnes : T, R" }) {
        val style = Type.serif(68).copy(letterSpacing = 3.sp)
        shown.forEachIndexed { index, c ->
            if (isVowel(c)) {
                val p = progress(index)
                Text(c.toString(), style = style, color = Palette.accent, softWrap = false, modifier = Modifier.collapse(p).alpha(p))
            } else Text(c.toString(), style = style, color = Palette.foreground, softWrap = false)
        }
    }
}

private fun ease(x: Float): Float { val t = x.coerceIn(0f, 1f); return t * t * (3 - 2 * t) }
