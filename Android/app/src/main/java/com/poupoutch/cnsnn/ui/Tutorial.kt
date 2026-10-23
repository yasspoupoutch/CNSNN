package com.poupoutch.cnsnn.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.material3.Surface
import com.poupoutch.cnsnn.core.Card
import com.poupoutch.cnsnn.core.Category
import com.poupoutch.cnsnn.core.Difficulty
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

/**
 * The places the first-launch tutorial points at: the daily card on the home page, then the real
 * Mot du jour page (played with an example word, never the real one).
 */
enum class TutorialTarget { DAILY, PLAY, TITLE, CLOCK, BOARD, HINT }

/** Where the targets are on screen, filled by the page and read by the overlay. */
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
val TUTORIAL_CARD = Card("seed-tutorial", "Auteur", "Il a écrit le livre.", Category.GENERAL, Difficulty.EASY)

enum class TutorialStep(val target: TutorialTarget, val title: String, val message: String, val word: String? = null) {
    PLAY(TutorialTarget.DAILY, "Le mot du jour", "Un nouveau mot chaque jour, le même pour tous. Appuyez sur Jouer !"),
    CONSONANTS(TutorialTarget.BOARD, "J’ai enlevé les voyelles",
        "Il ne reste que les consonnes, dans l’ordre. Ça peut être un mot, une ville, un pays, un film, un joueur… À vous de le retrouver !"),
    FIRST(TutorialTarget.BOARD, "Ça peut être TROU…", "Les voyelles O et U reviennent se glisser entre T et R.", "TROU"),
    SECOND(TutorialTarget.BOARD, "… ou AUTEUR…",
        "On repart de TR : cette fois, des voyelles se glissent aussi avant le T. Plusieurs mots sont possibles !", "AUTEUR"),
    TOP(TutorialTarget.TITLE, "Le thème et le chrono",
        "Sous les consonnes, le thème du mot pour vous mettre sur la piste. Le chrono, en haut à droite, part dès que vous appuyez sur Jouer."),
    HELP(TutorialTarget.HINT, "Si vous ne trouvez pas…", "… prenez un indice ! Appuyez sur Indice (+1 min sur le mot du jour)."),
}

/** The tutorial's progress on the Mot du jour page, shared by the board (which morphs the example) and the overlay. */
class TutorialDemo {
    var step by mutableStateOf(TutorialStep.CONSONANTS)
    /** The last step: Indice was tapped, the hint shows and AUTEUR slides in. */
    var hintShown by mutableStateOf(false)
    val word: String? get() = if (hintShown) "AUTEUR" else step.word
    val from: String? get() = if (step == TutorialStep.SECOND && !hintShown) TutorialStep.FIRST.word else null
}

val LocalTutorialDemo = staticCompositionLocalOf<TutorialDemo?> { null }

/**
 * First step, on the home page: the app dimmed around the daily card, Jouer ringed in pulsing gold.
 * Jouer is the only way on: it opens the real Mot du jour page for the rest.
 */
@Composable
fun TutorialOverlay(targets: TutorialTargets, play: () -> Unit, skip: () -> Unit) {
    val haptics = rememberHaptics()
    BackHandler(onBack = skip)
    TutorialStage(targets.rects[TutorialTarget.DAILY], 34.dp, ring = targets.rects[TutorialTarget.PLAY], ringTag = "tutorial.play", ringLabel = "Jouer",
        ringClick = { haptics.selection(); play() }, skip = skip) { arrowX, up ->
        TutorialBubble(TutorialStep.PLAY, false, arrowX, up)
    }
}

/**
 * The rest of the tutorial, over the real Mot du jour page: the consonants, the vowels sliding in, the
 * theme and the clock, then Indice, which really reveals the example's hint. [finish] gets true on
 * "À vous de jouer" (the real daily game opens next), false on "Passer".
 */
@Composable
fun TutorialGameOverlay(targets: TutorialTargets, demo: TutorialDemo, revealHint: () -> Unit, finish: (Boolean) -> Unit) {
    val haptics = rememberHaptics()
    fun next() {
        haptics.selection()
        if (demo.step == TutorialStep.HELP) finish(true)
        else { demo.step = TutorialStep.entries[demo.step.ordinal + 1]; demo.hintShown = false }
    }
    fun back() {
        haptics.selection()
        if (demo.step != TutorialStep.CONSONANTS) { demo.step = TutorialStep.entries[demo.step.ordinal - 1]; demo.hintShown = false }
    }
    BackHandler { if (demo.step == TutorialStep.CONSONANTS) finish(false) else back() }
    val rects = targets.rects
    val hole = when {
        // The theme line under the board; the bubble names the clock.
        demo.step == TutorialStep.TOP -> rects[TutorialTarget.TITLE]
        demo.step == TutorialStep.HELP && !demo.hintShown -> rects[TutorialTarget.HINT]
        else -> rects[TutorialTarget.BOARD]
    }
    val blinking = demo.step == TutorialStep.HELP && !demo.hintShown
    TutorialStage(hole, if (blinking) 24.dp else 26.dp, ring = if (blinking) rects[TutorialTarget.HINT] else null,
        ringTag = "tutorial.hint", ringLabel = "Indice", ringClick = { haptics.selection(); revealHint(); demo.hintShown = true },
        skip = { finish(false) }) { arrowX, up ->
        TutorialBubble(demo.step, demo.hintShown, arrowX, up, ::back, ::next)
    }
}

/**
 * The screen behind dimmed, a rounded hole over the part being explained, "Passer" at the top, an
 * optional gold ring to tap (Jouer, Indice), and the bubble right under the hole (or above it when the
 * hole is low on the screen).
 */
@Composable
private fun TutorialStage(target: Rect?, radiusDp: androidx.compose.ui.unit.Dp, ring: Rect?, ringTag: String, ringLabel: String,
                          ringClick: () -> Unit, skip: () -> Unit, bubble: @Composable (arrowX: Float, up: Boolean) -> Unit) {
    val density = LocalDensity.current
    var origin by remember { mutableStateOf(Offset.Zero) }
    var bounds by remember { mutableStateOf(Rect.Zero) }
    val inset = with(density) { 8.dp.toPx() }
    val hole = target?.translate(-origin)?.inflate(inset) ?: Rect(bounds.center, bounds.center)
    val lit = ring?.translate(-origin)?.inflate(with(density) { 6.dp.toPx() })
    val reduce = rememberReduceMotion()
    val animatedHole by animateValueAsState(hole, Rect.VectorConverter, if (reduce) tween(0) else tween(420), label = "hole")
    val radius = with(density) { radiusDp.toPx() }
    val pulse by rememberInfiniteTransition(label = "pulse").animateFloat(1f, if (reduce) 1f else 0.3f,
        infiniteRepeatable(tween(800), RepeatMode.Reverse), label = "pulse")
    val below = hole.center.y < bounds.height * 0.55f

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
            drawPath(path, Color.Black.copy(alpha = 0.5f))
            if (animatedHole.width > 1f) drawRoundRect(Color.White.copy(alpha = 0.35f), animatedHole.topLeft, animatedHole.size, CornerRadius(radius), style = Stroke(1.dp.toPx()))
            if (lit != null) {
                drawRoundRect(Palette.accent.copy(alpha = 0.18f * pulse), lit.topLeft, lit.size, CornerRadius(lit.height / 2))
                drawRoundRect(Palette.accent.copy(alpha = pulse), lit.topLeft, lit.size, CornerRadius(lit.height / 2), style = Stroke(2.5.dp.toPx()))
            }
        }
        // The ringed button can be tapped, like the real one.
        if (lit != null) {
            with(density) {
                Box(Modifier.offset { IntOffset(lit.left.roundToInt(), lit.top.roundToInt()) }.size(lit.width.toDp(), lit.height.toDp())
                    .clickable(role = Role.Button, onClick = ringClick)
                    .semantics { contentDescription = ringLabel }
                    .testTag(ringTag))
            }
        }
        TextButton(skip, Modifier.align(Alignment.TopEnd).statusBarsPadding().padding(end = 8.dp)
            .background(Color.Black.copy(alpha = 0.35f), RoundedCornerShape(50)).testTag("tutorial.skip")) {
            Text("Passer", color = Palette.foreground, fontWeight = FontWeight.SemiBold)
        }
        if (target != null) {
            val side = with(density) { 16.dp.toPx() }
            val arrowX = hole.center.x - side
            if (below) {
                val top = (hole.bottom + with(density) { 12.dp.toPx() }).roundToInt()
                Box(Modifier.fillMaxWidth().offset { IntOffset(0, top) }.padding(horizontal = 16.dp), contentAlignment = Alignment.TopCenter) {
                    bubble(arrowX, true)
                }
            } else {
                // Before the first measure the bounds are empty: never a negative padding.
                val bottom = with(density) { (bounds.height - hole.top + 12.dp.toPx()).coerceAtLeast(0f).toDp() }
                Box(Modifier.fillMaxSize().padding(start = 16.dp, end = 16.dp, bottom = bottom), contentAlignment = Alignment.BottomCenter) {
                    bubble(arrowX, false)
                }
            }
        }
    }
}

/**
 * The tutorial's speech bubble: light, raised, with an arrow toward the hole, so it reads as a note
 * laid over the app and not as one of its cards. On the home page Jouer is the only way on; on the hint
 * step, Indice first.
 */
@Composable
private fun TutorialBubble(step: TutorialStep, hintShown: Boolean, arrowX: Float, up: Boolean, back: (() -> Unit)? = null, next: (() -> Unit)? = null) {
    val ink = Palette.ink
    Column(Modifier.widthIn(max = 560.dp)) {
        if (up) Arrow(arrowX, true)
        Surface(shape = RoundedCornerShape(22.dp), color = Palette.foreground, shadowElevation = 12.dp) {
            AnimatedContent(step to hintShown, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "bubble") { (shown, hint) ->
                Column(Modifier.padding(18.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.semantics {
                        contentDescription = "Étape ${shown.ordinal + 1} sur ${TutorialStep.entries.size}"
                    }) {
                        TutorialStep.entries.forEach { item ->
                            Box(Modifier.height(6.dp).width(if (item == shown) 18.dp else 6.dp)
                                .background(if (item == shown) ink else ink.copy(alpha = 0.2f), RoundedCornerShape(3.dp)))
                        }
                    }
                    Text(shown.title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, color = ink,
                        modifier = Modifier.padding(top = 12.dp).semantics { heading() })
                    Text(if (shown == TutorialStep.HELP && hint) "« Il a écrit le livre. » : c’est AUTEUR ! À vous de trouver le mot du jour." else shown.message,
                        color = ink.copy(alpha = 0.75f), modifier = Modifier.padding(top = 6.dp))
                    if (next != null) Row(Modifier.fillMaxWidth().padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                        if (back != null && shown != TutorialStep.CONSONANTS) TextButton(back) { Text("Retour", color = ink.copy(alpha = 0.6f), fontWeight = FontWeight.SemiBold) }
                        Spacer(Modifier.weight(1f))
                        if (shown != TutorialStep.HELP || hint) {
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
        }
        if (!up) Arrow(arrowX, false)
    }
}

/** The bubble's little arrow, pointing up at the hole (bubble below it) or down (bubble above it). */
@Composable
private fun Arrow(x: Float, up: Boolean) {
    val color = Palette.foreground
    Canvas(Modifier.fillMaxWidth().height(10.dp)) {
        val half = 10.dp.toPx()
        val center = x.coerceIn(half + 14.dp.toPx(), size.width - half - 14.dp.toPx())
        val path = Path().apply {
            if (up) { moveTo(center - half, size.height); lineTo(center, 0f); lineTo(center + half, size.height) }
            else { moveTo(center - half, 0f); lineTo(center, size.height); lineTo(center + half, 0f) }
            close()
        }
        drawPath(path, color)
    }
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
fun MorphWord(word: String?, from: String?, size: Int = 68) {
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
        val style = Type.serif(size).copy(letterSpacing = 3.sp)
        shown.forEachIndexed { index, c ->
            if (isVowel(c)) {
                val p = progress(index)
                Text(c.toString(), style = style, color = Palette.accent, softWrap = false, modifier = Modifier.collapse(p).alpha(p))
            } else Text(c.toString(), style = style, color = Palette.foreground, softWrap = false)
        }
    }
}

private fun ease(x: Float): Float { val t = x.coerceIn(0f, 1f); return t * t * (3 - 2 * t) }
