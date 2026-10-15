package com.poupoutch.cnsnn.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt

/** Night background with two slow cool glows; gold stays for the vowels. */
@Composable
fun AmbientBackground(dimmed: Boolean = false) {
    val reduce = rememberReduceMotion()
    val drift = rememberInfiniteTransition(label = "drift")
    val t by drift.animateFloat(0f, 1f, infiniteRepeatable(tween(17_000, easing = LinearEasing), RepeatMode.Reverse), label = "t")
    val phase = if (reduce) 0.5f else t
    Canvas(Modifier.fillMaxSize()) {
        drawRect(Brush.radialGradient(listOf(Palette.backgroundTop, Palette.background), center = Offset(size.width / 2, 0f), radius = size.height * 0.7f))
        val k = if (dimmed) 0.55f else 1f
        val violet = Color(0xFF593EC7).copy(alpha = 0.5f * k)
        val teal = Color(0xFF007E86).copy(alpha = 0.45f * k)
        val r = size.width * 0.75f
        val c1 = Offset(size.width * (0.05f + 0.2f * phase), size.height * (0.05f + 0.15f * phase))
        val c2 = Offset(size.width * (0.95f - 0.25f * phase), size.height * (0.75f - 0.12f * phase))
        drawCircle(Brush.radialGradient(listOf(violet, violet.copy(alpha = 0f)), c1, r), r, c1)
        drawCircle(Brush.radialGradient(listOf(teal, teal.copy(alpha = 0f)), c2, r), r, c2)
    }
}

@Composable
fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    return remember {
        android.provider.Settings.Global.getFloat(context.contentResolver, android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
}

/** A word whose vowels are gold. */
fun highlighted(word: String, vowel: Color = Palette.accent, other: Color = Palette.foreground): AnnotatedString = buildAnnotatedString {
    for (c in word) withStyle(SpanStyle(color = if (isVowel(c)) vowel else other)) { append(c) }
}

/**
 * The wordmark: the vowels slide into the gaps between the consonants.
 * `once` plays it a single time (opening screen); otherwise it loops gently like the prototype.
 */
@Composable
fun VowelWord(word: String, style: TextStyle, modifier: Modifier = Modifier, once: Boolean = false, delayMs: Int = 0) {
    val reduce = rememberReduceMotion()
    val clock = remember { Animatable(0f) }
    LaunchedEffect(word) {
        if (reduce) return@LaunchedEffect
        if (once) clock.animateTo(10f, tween(10_000, easing = LinearEasing))
        else while (true) { clock.snapTo(0f); clock.animateTo(5f, tween(5_000, easing = LinearEasing)) }
    }
    Row(modifier.semantics { contentDescription = word }) {
        word.forEachIndexed { index, c ->
            if (isVowel(c)) {
                val time = clock.value - delayMs / 1000f - index * (if (once) INTRO_STAGGER else 0.12f)
                val p = if (reduce) 1f else if (once) intro(time) else loop(time)
                Text(c.toString(), style = style, color = Palette.accent, softWrap = false,
                    modifier = Modifier.collapse(p).alpha(p))
            } else Text(c.toString(), style = style, color = Palette.foreground, softWrap = false)
        }
    }
}
const val INTRO_STAGGER = 0.07f
private fun smooth(x: Float): Float { val t = x.coerceIn(0f, 1f); return t * t * (3 - 2 * t) }
private fun intro(time: Float) = smooth((time - 0.2f) / 0.35f)
private fun loop(time: Float): Float {
    val phase = ((time % 5f) + 5f) % 5f / 5f
    return when {
        phase < 0.22f -> 0f
        phase < 0.38f -> smooth((phase - 0.22f) / 0.16f)
        phase < 0.82f -> 1f
        else -> 1 - smooth((phase - 0.82f) / 0.18f)
    }
}
/** Opening length: the last vowel has settled, plus a short pause to read it. */
fun introDurationMs(word: String): Long {
    val last = word.indexOfLast { isVowel(it) }.coerceAtLeast(0)
    return ((0.2f + last * INTRO_STAGGER + 0.35f + 0.45f) * 1000).toLong()
}

/** Shrinks a child's width to a fraction of its natural width, so a letter can slide into a gap. */
fun Modifier.collapse(progress: Float) = clipToBounds().layout { measurable, constraints ->
    val placeable = measurable.measure(constraints.copy(minWidth = 0))
    val width = (placeable.width * progress.coerceIn(0f, 1f)).roundToInt()
    layout(width, placeable.height) { placeable.place((width - placeable.width) / 2, 0) }
}

@Composable
fun Avatar(name: String, colorIndex: Int, size: Dp, modifier: Modifier = Modifier) {
    Box(modifier.size(size).background(Palette.avatar(colorIndex), CircleShape)
        .border(1.5.dp, Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.55f), Color.Transparent)), CircleShape),
        contentAlignment = Alignment.Center) {
        Text(name.trim().firstOrNull()?.uppercase() ?: "?", color = Palette.ink, fontWeight = FontWeight.Bold, fontSize = (size.value * 0.43f).sp)
    }
}
fun colorIndex(id: String): Int = id.sumOf { it.code }

/** Main surface of a section: a softly lit card. */
@Composable
fun SectionCard(modifier: Modifier = Modifier, padding: Dp = 20.dp, radius: Dp = 28.dp, content: @Composable ColumnScope.() -> Unit) {
    // A translucent card matches no theme color, so its text would fall back to black: set it.
    Surface(modifier.fillMaxWidth(), shape = RoundedCornerShape(radius), color = Palette.surface.copy(alpha = 0.82f), contentColor = Palette.foreground,
        border = androidx.compose.foundation.BorderStroke(1.dp, Brush.verticalGradient(listOf(Palette.border, Palette.line)))) {
        Column(Modifier.padding(padding), content = content)
    }
}

@Composable
fun Kicker(text: String, color: Color = Palette.secondary, modifier: Modifier = Modifier) {
    Text(text.uppercase(), style = Type.kicker, color = color, modifier = modifier)
}

@Composable
fun LevelBar(value: Float, modifier: Modifier = Modifier) {
    LinearProgressIndicator(progress = { value.coerceIn(0f, 1f) }, modifier.fillMaxWidth().height(6.dp),
        color = Palette.foreground, trackColor = Palette.fill1, strokeCap = StrokeCap.Round, gapSize = 0.dp, drawStopIndicator = {})
}

@Composable
fun StatTile(value: String, label: String, modifier: Modifier = Modifier) {
    Surface(modifier, shape = RoundedCornerShape(20.dp), color = Palette.fill1) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 14.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(value, style = androidx.compose.material3.MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, maxLines = 1)
            Text(label, style = androidx.compose.material3.MaterialTheme.typography.bodySmall, color = Palette.secondary, maxLines = 2)
        }
    }
}

@Composable
fun ScreenTitle(text: String, modifier: Modifier = Modifier) {
    Text(text, style = androidx.compose.material3.MaterialTheme.typography.headlineLarge, modifier = modifier.padding(top = 8.dp, bottom = 4.dp))
}

@Composable
fun Divider() { Box(Modifier.fillMaxWidth().height(1.dp).background(Palette.line)) }
