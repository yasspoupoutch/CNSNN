package com.poupoutch.cnsnn.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.Shader
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.draw.BlurredEdgeTreatment
import android.graphics.Matrix
import android.graphics.SweepGradient
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.poupoutch.cnsnn.data.DailyStanding
import com.poupoutch.cnsnn.data.SprintRecord
import kotlinx.coroutines.delay
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.random.Random

// ---- Found word: letters bursting into confetti, then the Mot du jour place in big

private const val EXPLODE_AT = 0.55f
private const val BURST_DURATION = 3.0f
private val burstColors = listOf(Palette.accent, Palette.foreground, Palette.mint)

private class BurstParticle(
    val symbol: String, val x: Float, val y: Float, val vx: Float, val vy: Float,
    val drag: Float, val gravity: Float, val spin: Float, val turn: Float, val phase: Float, val scale: Float, val big: Boolean,
)

/**
 * A found word (Classique and Mot du jour): the word in big, a breath, then its letters burst and fall
 * as confetti (vowels gold, consonants ivory, a few turquoise). On the ranked Mot du jour the place follows
 * in big ("Vous êtes 12e"), then the result sheet comes up. A tap skips to the sheet. Same timings and
 * colours as the iPhone's WordCelebration.
 */
@Composable
fun WordCelebration(word: String, showsRank: Boolean, standing: () -> DailyStanding?, showSheet: () -> Unit, ended: () -> Unit) {
    val haptics = rememberHaptics()
    val measurer = rememberTextMeasurer()
    val letters = remember(word) { word.toList() }
    var t by remember { mutableFloatStateOf(0f) }
    var sheetUp by remember { mutableStateOf(false) }
    var place by remember { mutableStateOf<Triple<Int, Int, Int>?>(null) } // shown, rank, players
    var pop by remember { mutableStateOf(false) }
    val currentStanding by rememberUpdatedState(standing)
    val up = { if (!sheetUp) { sheetUp = true; place = null; showSheet() } }

    LaunchedEffect(Unit) {
        val start = withFrameNanos { it }
        while (t < BURST_DURATION) { t = (withFrameNanos { it } - start) / 1e9f }
    }
    LaunchedEffect(Unit) {
        delay((EXPLODE_AT * 1000).toLong())
        haptics.burst()
        if (!showsRank) { delay(250); up(); delay(((BURST_DURATION - EXPLODE_AT - 0.25f) * 1000).toLong()); ended(); return@LaunchedEffect }
        var waited = 0
        while (currentStanding()?.rank == null && waited < 3000) { delay(100); waited += 100 }
        val found = currentStanding(); val rank = found?.rank
        if (sheetUp || found == null || rank == null) { up(); delay(1500); ended(); return@LaunchedEffect }
        if (waited < 400) delay((400 - waited).toLong())
        val players = max(found.players, rank)
        place = Triple(players, rank, players)
        for (value in rankSteps(players, rank)) {
            delay(if (value - rank < 4) 120 else 45)
            if (sheetUp) return@LaunchedEffect
            place = Triple(value, rank, players); haptics.key()
        }
        haptics.success()
        pop = true; delay(250); pop = false
        delay(1400); up(); delay(500); ended()
    }

    BoxWithConstraints(Modifier.fillMaxSize()
        .then(if (sheetUp) Modifier else Modifier.clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { up(); ended() })) {
        val density = androidx.compose.ui.platform.LocalDensity.current
        val widthPx = with(density) { maxWidth.toPx() }; val heightPx = with(density) { maxHeight.toPx() }
        val centerY = heightPx * 0.36f
        val sizePx = min(with(density) { 60.dp.toPx() }, widthPx * 0.86f / (max(letters.size, 1) * 0.68f))
        val step = sizePx * 0.68f
        val xs = remember(letters, widthPx) { letters.indices.map { widthPx / 2 + (it - (letters.size - 1) / 2f) * step } }
        val sizeSp = with(density) { sizePx.toSp() }
        // Each letter measured once: the word's letters in big, and the small confetti letters per colour.
        val symbols = remember(letters, sizeSp) {
            val map = HashMap<String, TextLayoutResult>()
            letters.forEachIndexed { i, c ->
                map["w$i"] = measurer.measure(c.toString(), TextStyle(fontSize = sizeSp, fontWeight = FontWeight.Black, color = if (isVowel(c)) Palette.accent else Palette.foreground))
            }
            letters.map { it.toString() }.toSet().forEach { c ->
                burstColors.forEachIndexed { ci, color -> map["s$c$ci"] = measurer.measure(c, TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Black, color = color)) }
            }
            map
        }
        val particles = remember(letters, widthPx) { burstParticles(letters, xs, centerY) }
        Canvas(Modifier.fillMaxSize()) {
            if (t < EXPLODE_AT) {
                val tension = max(0f, (t - 0.25f) / (EXPLODE_AT - 0.25f)); val scale = 1 + 0.08f * tension; val shake = 2 * tension
                drawCircle(Brush.radialGradient(listOf(Palette.accent.copy(alpha = 0.35f * tension), Color.Transparent), Offset(size.width / 2, centerY), 180.dp.toPx()),
                    radius = 180.dp.toPx(), center = Offset(size.width / 2, centerY))
                letters.indices.forEach { i ->
                    val layout = symbols["w$i"] ?: return@forEach
                    val x = size.width / 2 + (xs[i] - size.width / 2) * scale + (Random.nextFloat() - 0.5f) * 2 * shake
                    translate(x, centerY + (Random.nextFloat() - 0.5f) * 2 * shake) {
                        scale(scale, Offset.Zero) { drawText(layout, topLeft = Offset(-layout.size.width / 2f, -layout.size.height / 2f)) }
                    }
                }
                return@Canvas
            }
            val s = t - EXPLODE_AT
            if (s < 0.25f) drawRect(Brush.radialGradient(listOf(Color(0xFFFFF2C4).copy(alpha = 0.7f * (1 - s / 0.25f)), Palette.accent.copy(alpha = 0.35f * (1 - s / 0.25f)), Color.Transparent),
                Offset(size.width / 2, centerY), 260.dp.toPx()))
            val fade = ((BURST_DURATION - t) / 0.6f).coerceIn(0f, 1f)
            for (p in particles) {
                val layout = symbols[p.symbol] ?: continue
                val e = exp(-p.drag * s); val travel = (1 - e) / p.drag
                val x = p.x + p.vx * travel + if (p.big) 0f else sin(s * 4 + p.phase) * 8.dp.toPx() / 2
                val y = p.y + p.vy * travel + p.gravity / p.drag * (s - travel)
                if (y > size.height + 60) continue
                translate(x, y) {
                    rotate(Math.toDegrees((p.spin + p.turn * s).toDouble()).toFloat(), Offset.Zero) {
                        scale(p.scale * (if (p.big) 1f else cos(s * 4 + p.phase)), p.scale, Offset.Zero) {
                            drawText(layout, topLeft = Offset(-layout.size.width / 2f, -layout.size.height / 2f), alpha = fade)
                        }
                    }
                }
            }
        }
        val shown = place
        AnimatedVisibility(shown != null, Modifier.align(Alignment.TopCenter).offset(y = with(density) { centerY.toDp() } - 110.dp),
            enter = fadeIn() + scaleIn(initialScale = 0.85f), exit = fadeOut(tween(250))) {
            shown?.let { RankReveal(it.first, it.third, pop) }
        }
    }
}

/** From the number of players down to the place, in shrinking jumps (about 12 steps). */
internal fun rankSteps(players: Int, rank: Int): List<Int> {
    val values = mutableListOf<Int>(); var value = players
    while (value > rank) { value = max(rank, value - max(1, ((value - rank) / 5.0).roundToInt())); values += value }
    return values
}

private fun burstParticles(letters: List<Char>, xs: List<Float>, y: Float): List<BurstParticle> {
    if (letters.isEmpty()) return emptyList()
    val perLetter = (100 / letters.size).coerceIn(4, 11)
    val middle = xs[letters.size / 2]
    val all = mutableListOf<BurstParticle>()
    fun r(a: Float, b: Float) = a + Random.nextFloat() * (b - a)
    letters.forEachIndexed { i, c ->
        val x = xs[i]
        all += BurstParticle("w$i", x, y, (x - middle) * 2.4f + r(-80f, 80f), r(-520f, -260f), 0.5f, 1100f, 0f, r(-5f, 5f), 0f, 1f, true)
        repeat(perLetter) {
            val angle = r(0f, 2 * PI.toFloat()); val speed = r(160f, 580f)
            val pick = letters.random(); val color = if (Random.nextFloat() < 0.15f) 2 else if (isVowel(pick)) 0 else 1
            all += BurstParticle("s$pick$color", x + r(-10f, 10f), y + r(-20f, 20f), cos(angle) * speed, sin(angle) * speed - 220f,
                2.6f, 620f, r(0f, 6f), r(-6f, 6f), r(0f, 6f), r(0.6f, 1.3f), false)
        }
    }
    return all
}

@Composable
private fun RankReveal(shown: Int, players: Int, pop: Boolean) {
    val scale by animateFloatAsState(if (pop) 1.12f else 1f, spring(dampingRatio = 0.45f), label = "pop")
    val gold = Brush.verticalGradient(listOf(Color(0xFFFFF0C4), Palette.accent))
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text("Vous êtes", style = Type.serifItalic(30), color = Palette.foreground.copy(alpha = 0.85f))
        Row(Modifier.scale(scale), verticalAlignment = Alignment.Top) {
            Text("$shown", style = TextStyle(brush = gold, fontSize = 120.sp, fontWeight = FontWeight.Black, lineHeight = 124.sp), maxLines = 1)
            Text(if (shown == 1) "er" else "e", style = TextStyle(brush = gold, fontSize = 44.sp, fontWeight = FontWeight.Black), modifier = Modifier.padding(top = 18.dp))
        }
        Text("sur $players joueur${if (players > 1) "s" else ""} aujourd’hui", color = Palette.secondary, fontSize = 16.sp)
    }
}

// ---- Sprint: the record bar and its halo

/**
 * The Sprint progress: a bar of the words found, marked with the player's record and the game's record
 * (when within reach: at most 1.5 times the player's record). A halo of light turns around it once two
 * words follow in a row, faster and brighter as the streak grows. Each word makes it leap and flash;
 * nothing here delays the next word. Same rules as the iPhone's SprintRecordBar.
 */
@Composable
fun SprintRecordBar(found: Int, streak: Int, accuracy: Int, personal: Int, leader: SprintRecord?, me: String?, pulse: Int, modifier: Modifier = Modifier) {
    val reduceMotion = rememberReduceMotion()
    val goal = if (personal > 0) personal else 10
    val gameRecord = leader?.takeIf { it.uid != me && it.best > personal && it.best <= goal * 1.5 }
    val scaleMax = maxOf(maxOf(goal, gameRecord?.best ?: 0) * 1.2, found + 2.0, 10.0)
    val level = when { streak >= 8 -> 4; streak >= 5 -> 3; streak >= 3 -> 2; streak >= 2 -> 1; else -> 0 }
    val beatMine = personal > 0 && found > personal
    var flash by remember { mutableStateOf(false) }
    LaunchedEffect(pulse) { if (pulse > 0 && !reduceMotion) { flash = true; delay(220); flash = false } }
    val fill by animateFloatAsState(min(1f, (found / scaleMax).toFloat()), if (reduceMotion) tween(0) else spring(dampingRatio = 0.55f, stiffness = 300f), label = "fill")
    val glow by animateFloatAsState(if (flash) 1f else 0f, tween(if (flash) 120 else 300), label = "flash")
    val streakText = when { streak >= 8 -> "Inarrêtable ×$streak"; streak >= 5 -> "Quelle série ×$streak"; streak >= 3 -> "Belle série ×$streak"; else -> "Combo ×${maxOf(1, streak)}" }
    Column(modifier.fillMaxWidth().semantics {
        contentDescription = "$found mot${if (found > 1) "s" else ""}, " + (if (personal > 0) "votre record : $personal" else "objectif : 10") + (if (streak >= 2) ", série de $streak" else "")
    }) {
        Row(Modifier.fillMaxWidth().height(22.dp), verticalAlignment = Alignment.CenterVertically) {
            if (streak >= 2) Text(streakText, style = Type.serifItalic(17), color = Palette.accent)
            else Text(streakText, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Palette.tertiary)
            Box(Modifier.weight(1f))
            Text("$accuracy % précision", fontSize = 12.sp, color = Palette.tertiary)
        }
        BoxWithConstraints(Modifier.fillMaxWidth().padding(top = 6.dp)) {
            val width = maxWidth
            fun x(value: Int) = width * min(1f, (value / scaleMax).toFloat())
            Column {
                Box(Modifier.fillMaxWidth().height(18.dp).scale(1f + 0.03f * glow)) {
                    BarHalo(level, Modifier.matchParentSize())
                    Box(Modifier.fillMaxSize().background(Palette.fill1, RoundedCornerShape(9.dp)).border(1.dp, Palette.line, RoundedCornerShape(9.dp)))
                    val fillColors = if (beatMine) listOf(Palette.accent, Color(0xFFFFF2CC)) else listOf(Palette.accentBottom, Palette.accentTop)
                    Box(Modifier.width(maxOf(18.dp, width * fill)).height(18.dp)
                        .drawBehind { if (glow > 0f) drawRoundRect(Palette.accent.copy(alpha = 0.5f * glow), topLeft = Offset(-6f, -6f), size = Size(size.width + 12f, size.height + 12f), cornerRadius = CornerRadius(30f)) }
                        .background(Brush.horizontalGradient(fillColors.map { if (glow > 0f) lerpWhite(it, 0.25f * glow) else it }), RoundedCornerShape(9.dp)),
                        contentAlignment = Alignment.CenterEnd) {
                        Text("$found", fontSize = 11.sp, fontWeight = FontWeight.Black, color = Palette.ink, modifier = Modifier.padding(end = 6.dp))
                    }
                    Tick(x(goal)); gameRecord?.let { Tick(x(it.best)) }
                }
                MarkLabel(if (personal > 0) (if (beatMine) "Record battu !" else "Ton record $personal") else "Objectif 10", beatMine || (personal == 0 && found >= 10), x(goal), width)
                gameRecord?.let { record ->
                    val text = when { found > record.best -> "Record du jeu : toi !"; found >= record.best - 2 -> "Plus que ${record.best - found + 1} !"; else -> "Record du jeu · ${record.username} ${record.best}" }
                    MarkLabel(text, found >= record.best - 2, x(record.best), width)
                }
            }
        }
    }
}

private fun lerpWhite(c: Color, f: Float) = Color(c.red + (1 - c.red) * f, c.green + (1 - c.green) * f, c.blue + (1 - c.blue) * f, c.alpha)

@Composable
private fun Tick(x: androidx.compose.ui.unit.Dp) {
    Box(Modifier.offset(x = x - 0.75.dp, y = 7.dp).width(1.5.dp).height(26.dp).background(Palette.foreground.copy(alpha = 0.5f)))
}

/** A label whose right edge sits on its mark (kept inside the bar's width). */
@Composable
private fun MarkLabel(text: String, done: Boolean, x: androidx.compose.ui.unit.Dp, width: androidx.compose.ui.unit.Dp) {
    Box(Modifier.width(minOf(width, maxOf(x + 1.dp, 150.dp))).padding(top = 4.dp), contentAlignment = Alignment.CenterEnd) {
        Text(text, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = if (done) Palette.accent else Palette.tertiary, maxLines = 1, softWrap = false, overflow = TextOverflow.Visible)
    }
}

/** A light turning around the Sprint bar: off below two words in a row, faster and brighter with the streak, two lights from eight. */
@Composable
private fun BarHalo(level: Int, modifier: Modifier) {
    val reduceMotion = rememberReduceMotion()
    val period = floatArrayOf(5f, 4.5f, 3.2f, 1.9f, 1.1f)[level]
    val alpha by animateFloatAsState(floatArrayOf(0f, 0.5f, 0.7f, 0.9f, 1f)[level], tween(400), label = "halo")
    var turn by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(level, reduceMotion) {
        if (level == 0 || reduceMotion) return@LaunchedEffect
        var last = withFrameNanos { it }
        while (true) { val now = withFrameNanos { it }; turn = (turn + (now - last) / 1e9f / period * 360f) % 360f; last = now }
    }
    if (alpha <= 0.01f) return
    val gold = Palette.accent.toArgb(); val white = Color(0xFFFFF7DB).toArgb(); val clear = Color.Transparent.toArgb()
    val colors = if (level >= 4) intArrayOf(clear, white, clear, clear, white, clear, clear) else intArrayOf(clear, clear, gold, white, gold, clear)
    val stops = if (level >= 4) floatArrayOf(0f, 0.2f, 0.4f, 0.5f, 0.7f, 0.9f, 1f) else floatArrayOf(0f, 0.55f, 0.82f, 0.9f, 0.95f, 1f)
    val draw: DrawScope.() -> Unit = {
        val cx = size.width / 2; val cy = size.height / 2
        val brush = object : ShaderBrush() {
            override fun createShader(size: Size): Shader = SweepGradient(cx, cy, colors, stops).apply { setLocalMatrix(Matrix().apply { setRotate(turn, cx, cy) }) }
        }
        val pad = 3.dp.toPx()
        drawRoundRect(brush, topLeft = Offset(-pad, -pad), size = Size(size.width + 2 * pad, size.height + 2 * pad),
            cornerRadius = CornerRadius(size.height / 2 + pad), style = Stroke(2.dp.toPx()))
    }
    Box(modifier.alpha(alpha)) {
        Canvas(Modifier.matchParentSize().blur(6.dp, BlurredEdgeTreatment.Unbounded)) { draw() }
        Canvas(Modifier.matchParentSize()) { draw() }
    }
}
