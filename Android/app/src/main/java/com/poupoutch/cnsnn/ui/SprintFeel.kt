package com.poupoutch.cnsnn.ui

import android.content.Context
import android.graphics.Matrix
import android.graphics.SweepGradient
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shader
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.poupoutch.cnsnn.data.SprintRecord
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.random.Random

/** The Sprint bar's heat: white, then pale gold (2 in a row), gold (3), orange (5), red-orange (8 and more). Same as the iPhone. */
object SprintHeat {
    private val stops = listOf(0 to Color(0xFFF4F5F8), 2 to Color(0xFFFFE7A8), 3 to Color(0xFFFFC65A), 5 to Color(0xFFFF963C), 8 to Color(0xFFFF6028))
    fun color(streak: Int): Color {
        val k = max(0, streak)
        val upper = stops.indexOfFirst { it.first >= k }
        if (upper <= 0) return if (k >= 8) stops.last().second else stops.first().second
        val (a, b) = stops[upper - 1] to stops[upper]
        return lerp(a.second, b.second, (k - a.first).toFloat() / (b.first - a.first))
    }
    /** The glow around the fill. */
    fun glow(streak: Int): Dp = when { streak >= 8 -> 16.dp; streak >= 5 -> 11.dp; streak >= 3 -> 7.dp; else -> 4.dp }
}

/**
 * The Sprint progress: a bar of the words found that starts white and heats up with the streak (a
 * mistake cools it back), the record game of this phone running along it as a pale ghost ("+2 sur ton
 * record"), the player's and the game's record marks, and a light turning around it faster with each
 * word in a row. Nothing here delays the next word. Same rules as the iPhone's SprintRecordBar.
 */
@Composable
fun SprintRecordBar(found: Int, streak: Int, accuracy: Int, personal: Int, leader: SprintRecord?, me: String?, pulse: Int, ghost: Int?, modifier: Modifier = Modifier) {
    val reduceMotion = rememberReduceMotion()
    val goal = if (personal > 0) personal else 10
    val gameRecord = leader?.takeIf { it.uid != me && it.best > personal && it.best <= goal * 1.5 }
    val scaleMax = maxOf(maxOf(goal, gameRecord?.best ?: 0) * 1.2, found + 2.0, 10.0)
    val heat by animateColorAsState(SprintHeat.color(streak), tween(if (reduceMotion) 0 else 500), label = "heat")
    val lead = ghost?.let { found - it }
    var flash by remember { mutableStateOf(false) }
    var overtake by remember { mutableStateOf(false) }
    LaunchedEffect(pulse) { if (pulse > 0 && !reduceMotion) { flash = true; delay(220); flash = false } }
    var lastLead by remember { mutableStateOf(lead ?: 0) }
    LaunchedEffect(lead) {
        val before = lastLead; lastLead = lead ?: 0
        // Passing ahead of the record's ghost: a short green flash.
        if (lead != null && before <= 0 && lead > 0 && !reduceMotion) { overtake = true; delay(350); overtake = false }
    }
    val fill by animateFloatAsState(min(1f, (found / scaleMax).toFloat()), if (reduceMotion) tween(0) else spring(dampingRatio = 0.55f, stiffness = 300f), label = "fill")
    val ghostFill by animateFloatAsState(min(1f, ((ghost ?: 0) / scaleMax).toFloat()), tween(if (reduceMotion) 0 else 800, easing = FastOutSlowInEasing), label = "ghost")
    val glow by animateFloatAsState(if (flash || overtake) 1f else 0f, tween(if (flash || overtake) 120 else 300), label = "flash")
    val leadScale by animateFloatAsState(if (overtake) 1.2f else 1f, spring(dampingRatio = 0.5f), label = "lead")
    val streakText = when { streak >= 8 -> "Inarrêtable ×$streak"; streak >= 5 -> "Quelle série ×$streak"; streak >= 3 -> "Belle série ×$streak"; else -> "Combo ×${maxOf(1, streak)}" }
    val leadText = when { lead == null -> "$accuracy % précision"; lead > 0 -> "+$lead sur ton record"; lead < 0 -> "−${-lead} sur ton record"; else -> "à égalité avec ton record" }
    Column(modifier.fillMaxWidth().semantics {
        contentDescription = "$found mot${if (found > 1) "s" else ""}, " + (if (personal > 0) "votre record : $personal" else "objectif : 10") + (if (streak >= 2) ", série de $streak" else "") +
            (lead?.let { if (it > 0) ", $it d’avance sur votre record" else if (it < 0) ", ${-it} de retard sur votre record" else "" } ?: "")
    }) {
        Row(Modifier.fillMaxWidth().height(22.dp), verticalAlignment = Alignment.CenterVertically) {
            if (streak >= 2) Text(streakText, style = Type.serifItalic(17), color = heat)
            else Text(streakText, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Palette.tertiary)
            Box(Modifier.weight(1f))
            Text(leadText, fontSize = 12.sp, fontWeight = if ((lead ?: 0) > 0) FontWeight.Bold else FontWeight.Normal,
                color = if ((lead ?: 0) > 0) Palette.mint else Palette.tertiary, modifier = Modifier.scale(leadScale))
        }
        BoxWithConstraints(Modifier.fillMaxWidth().padding(top = 6.dp)) {
            val width = maxWidth
            fun x(value: Int) = width * min(1f, (value / scaleMax).toFloat())
            Column {
                Box(Modifier.fillMaxWidth().height(18.dp).scale(1f + 0.03f * glow)) {
                    BarHalo(streak, found > 0, heat, Modifier.matchParentSize())
                    Box(Modifier.fillMaxSize().background(Palette.fill1, RoundedCornerShape(9.dp)).border(1.dp, Palette.line, RoundedCornerShape(9.dp)))
                    if ((ghost ?: 0) > 0) {
                        Box(Modifier.width(maxOf(18.dp, width * ghostFill)).height(18.dp).background(Palette.foreground.copy(alpha = 0.16f), RoundedCornerShape(9.dp)),
                            contentAlignment = Alignment.CenterEnd) {
                            Box(Modifier.width(2.dp).height(12.dp).background(Palette.foreground.copy(alpha = 0.55f), RoundedCornerShape(1.dp)))
                        }
                    }
                    val shine = if (overtake) Palette.mint else heat
                    val glowRadius = if (flash || overtake) 14.dp else SprintHeat.glow(streak)
                    Box(Modifier.width(maxOf(18.dp, width * fill)).height(18.dp)
                        .drawBehind {
                            val r = glowRadius.toPx()
                            drawRoundRect(Brush.radialGradient(listOf(shine.copy(alpha = if (flash || overtake) 0.55f else 0.3f), Color.Transparent),
                                center = Offset(size.width / 2, size.height / 2), radius = max(size.width, size.height) / 2 + r),
                                topLeft = Offset(-r, -r), size = Size(size.width + 2 * r, size.height + 2 * r), cornerRadius = CornerRadius(size.height / 2 + r))
                        }
                        .background(lerp(heat, Color.White, 0.18f * glow), RoundedCornerShape(9.dp))
                        .background(Brush.horizontalGradient(listOf(Color.Black.copy(alpha = 0.14f), Color.White.copy(alpha = 0.22f))), RoundedCornerShape(9.dp)),
                        contentAlignment = Alignment.CenterEnd) {
                        Text("$found", fontSize = 11.sp, fontWeight = FontWeight.Black, color = Palette.ink, modifier = Modifier.padding(end = 6.dp))
                    }
                    Tick(x(goal)); gameRecord?.let { Tick(x(it.best)) }
                }
                MarkLabel(if (personal > 0) (if (found > personal) "Record battu !" else "Ton record $personal") else "Objectif 10",
                    found > personal && (personal > 0 || found >= 10), x(goal), width)
                gameRecord?.let { record ->
                    val text = when { found > record.best -> "Record du jeu : toi !"; found >= record.best - 2 -> "Plus que ${record.best - found + 1} !"; else -> "Record du jeu · ${record.username} ${record.best}" }
                    MarkLabel(text, found >= record.best - 2, x(record.best), width)
                }
            }
        }
    }
}

@Composable
private fun Tick(x: Dp) {
    Box(Modifier.offset(x = x - 0.75.dp, y = 7.dp).width(1.5.dp).height(26.dp).background(Palette.foreground.copy(alpha = 0.5f)))
}

/** A label whose right edge sits on its mark (kept inside the bar's width). */
@Composable
private fun MarkLabel(text: String, done: Boolean, x: Dp, width: Dp) {
    Box(Modifier.width(minOf(width, maxOf(x + 1.dp, 150.dp))).padding(top = 4.dp), contentAlignment = Alignment.CenterEnd) {
        Text(text, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = if (done) Palette.accent else Palette.tertiary, maxLines = 1, softWrap = false, overflow = TextOverflow.Visible)
    }
}

/**
 * A light turning around the Sprint bar, from the first word: one turn in 6 seconds, then 18 % faster
 * with each word in a row (down to 0.6 s a turn). The angle adds up frame by frame and the speed eases
 * toward its new value, so a change never makes the light jump or blink; a mistake slows it down
 * gently. Still with reduced motion. Same as the iPhone's BarHalo.
 */
@Composable
private fun BarHalo(streak: Int, shown: Boolean, color: Color, modifier: Modifier) {
    val reduceMotion = rememberReduceMotion()
    val target = 360f / max(0.6f, 6f * 0.82f.pow(max(0, streak - 1)))
    val currentTarget by rememberUpdatedState(target)
    val alpha by animateFloatAsState(if (shown) min(1f, 0.45f + streak * 0.07f) else 0f, tween(1200), label = "halo")
    var turn by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(shown, reduceMotion) {
        if (!shown || reduceMotion) return@LaunchedEffect
        var speed = 60f
        var last = withFrameNanos { it }
        while (true) {
            val now = withFrameNanos { it }
            val dt = min(0.05f, (now - last) / 1e9f); last = now
            speed += (currentTarget - speed) * min(1f, dt * 2.2f)
            turn = (turn + speed * dt) % 360f
        }
    }
    if (alpha <= 0.01f) return
    val c = color.toArgb(); val white = Color(0xFFFFF7DB).toArgb(); val clear = color.copy(alpha = 0f).toArgb()
    val colors = intArrayOf(clear, clear, c, white, c, clear)
    val stops = floatArrayOf(0f, 0.55f, 0.82f, 0.9f, 0.95f, 1f)
    val draw: DrawScope.(Float) -> Unit = { width ->
        val cx = size.width / 2; val cy = size.height / 2
        val brush = object : ShaderBrush() {
            override fun createShader(size: Size): Shader = SweepGradient(cx, cy, colors, stops).apply { setLocalMatrix(Matrix().apply { setRotate(turn, cx, cy) }) }
        }
        val pad = 3.dp.toPx()
        drawRoundRect(brush, topLeft = Offset(-pad, -pad), size = Size(size.width + 2 * pad, size.height + 2 * pad),
            cornerRadius = CornerRadius(size.height / 2 + pad), style = Stroke(width))
    }
    Box(modifier.alpha(alpha)) {
        Canvas(Modifier.matchParentSize().blur(6.dp, BlurredEdgeTreatment.Unbounded)) { draw(2.5.dp.toPx()) }
        Canvas(Modifier.matchParentSize()) { draw(2.dp.toPx()) }
    }
}

/**
 * Sprint: the word just found turns gold and floats up from the answer line, fading out in 0.4 s, and
 * the line under it lights up gold. The next word is already on screen and the keyboard keeps working.
 */
@Composable
fun FlyingWord(word: String?, tick: Int, modifier: Modifier = Modifier) {
    val reduceMotion = rememberReduceMotion()
    val flights = remember { mutableStateListOf<Pair<Int, String>>() }
    val lit = remember { Animatable(0f) }
    LaunchedEffect(tick) {
        if (tick <= 0 || reduceMotion || word == null) return@LaunchedEffect
        flights += tick to word.uppercase()
        launch { lit.snapTo(1f); delay(60); lit.animateTo(0f, tween(400)) }
        delay(500); flights.removeAll { it.first == tick }
    }
    Box(modifier) {
        flights.forEach { (id, text) -> androidx.compose.runtime.key(id) { FlightText(text, Modifier.align(Alignment.Center)) } }
        if (lit.value > 0f) Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(1.5.dp).alpha(lit.value)
            .drawBehind { drawRect(Brush.verticalGradient(listOf(Color.Transparent, Palette.accent.copy(alpha = 0.6f), Color.Transparent), startY = -12f, endY = size.height + 12f), Offset(0f, -12f), Size(size.width, size.height + 24f)) }
            .background(Palette.accent))
    }
}

@Composable
private fun FlightText(word: String, modifier: Modifier) {
    val up = remember { Animatable(0f) }
    LaunchedEffect(Unit) { up.animateTo(1f, tween(400, easing = FastOutSlowInEasing)) }
    val p = up.value
    val density = LocalDensity.current
    Text(word, fontSize = if (word.length > 14) 22.sp else 30.sp, fontWeight = FontWeight.Medium, letterSpacing = 2.sp, maxLines = 1, color = Palette.accent,
        style = TextStyle(shadow = androidx.compose.ui.graphics.Shadow(Palette.accent.copy(alpha = 0.6f), blurRadius = 16f)),
        modifier = modifier.graphicsLayer {
            translationY = with(density) { (-4f - 40f * p).dp.toPx() }
            val s = 1.12f - 0.22f * p; scaleX = s; scaleY = s
            alpha = 1f - p
        })
}

/** The bar inside the Sprint results: it fills as the score counts up, past the old record (which turns gold) toward the game record when someone else holds it. */
@Composable
fun ResultRecordBar(value: Int, personal: Int, leader: SprintRecord?, me: String?, beaten: Boolean, modifier: Modifier = Modifier) {
    val other = leader?.takeIf { it.uid != me && it.best > personal }
    val scaleMax = max(maxOf(personal, other?.best ?: 0, 10) * 1.15, value + 1.0)
    val fill by animateFloatAsState((value / scaleMax).toFloat(), tween(120), label = "result")
    BoxWithConstraints(modifier.fillMaxWidth().height(50.dp)) {
        val width = maxWidth
        fun x(v: Int) = width * (v / scaleMax).toFloat()
        Box(Modifier.offset(y = 20.dp).fillMaxWidth().height(12.dp).background(Palette.fill1, RoundedCornerShape(6.dp)))
        val colors = if (beaten) listOf(Palette.accent, Color(0xFFFFF2CC)) else listOf(Palette.accentBottom, Palette.accentTop)
        Box(Modifier.offset(y = 20.dp).width(maxOf(12.dp, width * fill)).height(12.dp)
            .drawBehind {
                if (beaten) {
                    val r = 10.dp.toPx()
                    drawRoundRect(Brush.radialGradient(listOf(Palette.accent.copy(alpha = 0.5f), Color.Transparent), Offset(size.width / 2, size.height / 2), size.width / 2 + r),
                        Offset(-r, -r), Size(size.width + 2 * r, size.height + 2 * r), CornerRadius(size.height / 2 + r))
                }
            }
            .background(Brush.horizontalGradient(colors), RoundedCornerShape(6.dp)))
        if (personal > 0) ResultMark("Ton record $personal", x(personal), beaten, above = false)
        other?.let { ResultMark("${it.username} ${it.best}", x(it.best), false, above = true) }
    }
}

@Composable
private fun ResultMark(text: String, x: Dp, gold: Boolean, above: Boolean) {
    Box(Modifier.offset(x = x - 0.75.dp, y = 16.dp).width(1.5.dp).height(20.dp).background(Palette.foreground.copy(alpha = 0.5f)))
    Box(Modifier.offset(x = x - 80.dp, y = if (above) 0.dp else 36.dp).width(160.dp), contentAlignment = Alignment.Center) {
        Text(text, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = if (gold) Palette.accent else Palette.tertiary, maxLines = 1, softWrap = false, overflow = TextOverflow.Visible)
    }
}

/** Gold vowels falling over the whole screen for a beaten Sprint record (about 4 seconds). Same as the iPhone's VowelRain. */
@Composable
fun VowelRain(modifier: Modifier = Modifier) {
    class Drop(val letter: String, val x: Float, val size: Int, val delay: Float, val duration: Float, val turn: Float)
    val drops = remember { List(46) { i -> Drop("AEIOU"[i % 5].toString(), Random.nextFloat(), 18 + Random.nextInt(35), Random.nextFloat() * 0.9f, 2.2f + Random.nextFloat() * 1.6f, -270f + Random.nextFloat() * 540f) } }
    val measurer = rememberTextMeasurer()
    val layouts = remember { HashMap<String, TextLayoutResult>() }
    var t by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(Unit) {
        val start = withFrameNanos { it }
        while (t < 4.8f) { t = (withFrameNanos { it } - start) / 1e9f }
    }
    if (t >= 4.8f) return
    Canvas(modifier.fillMaxSize()) {
        for (drop in drops) {
            val p = (t - drop.delay) / drop.duration
            if (p <= 0f || p >= 1f) continue
            val key = drop.letter + drop.size
            val layout = layouts.getOrPut(key) { measurer.measure(drop.letter, Type.serif(drop.size).copy(color = Palette.accent)) }
            val y = -60.dp.toPx() + (size.height + 120.dp.toPx()) * p.pow(1.4f)
            translate(drop.x * size.width, y) {
                rotate(drop.turn * p, Offset.Zero) {
                    drawText(layout, topLeft = Offset(-layout.size.width / 2f, -layout.size.height / 2f), alpha = 1f - 0.1f * p)
                }
            }
        }
    }
}

/**
 * Sprint notes made in code (the iPhone's SprintSound): a pentatonic scale that rises with each word in
 * a row, a chord at 5 and 8 in a row, three notes for a beaten record, a soft low note for a mistake.
 * Silent when the phone is on vibrate or silent; mixes with the player's music.
 */
object SprintSound {
    private val scale = intArrayOf(0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24, 26, 28)
    val steps: Int get() = scale.size
    private const val BASE = 523.25
    private const val RATE = 44_100
    private val cache = HashMap<String, ShortArray>()
    private val main = Handler(Looper.getMainLooper())

    private fun freq(semitones: Int) = BASE * 2.0.pow(semitones / 12.0)
    private fun step(n: Int) = scale[(max(1, n) - 1).coerceAtMost(scale.size - 1)]

    fun note(context: Context, n: Int) { val s = step(n); play(context, "n$s") { mix(0.35, listOf(Triple(freq(s), 0.0, 0.16))) } }
    fun chord(context: Context, n: Int) {
        val s = step(n)
        play(context, "c$s") { mix(0.7, listOf(0, 4, 7, 12).mapIndexed { i, d -> Triple(freq(s + d - 12), i * 0.035, 0.07) }) }
    }
    fun record(context: Context) = play(context, "r") { mix(0.45, listOf(0, 4, 7, 12).mapIndexed { i, d -> Triple(freq(d + 7), i * 0.09, 0.11) }) }
    fun miss(context: Context) = play(context, "m") { mix(0.25, listOf(Triple(150.0, 0.0, 0.18))) }

    /** Tones (frequency, start in s, volume), each [length] seconds: a sine with a little octave, 8 ms attack, a falling tail. */
    private fun mix(length: Double, tones: List<Triple<Double, Double, Double>>): ShortArray {
        val total = ((length + (tones.maxOfOrNull { it.second } ?: 0.0)) * RATE).toInt() + 1
        val out = DoubleArray(total)
        val attack = 0.008; val decay = ln(0.0001) / length
        for ((f, at, volume) in tones) {
            val start = (at * RATE).toInt()
            val count = (length * RATE).toInt()
            for (i in 0 until count) {
                val time = i.toDouble() / RATE
                val env = if (time < attack) time / attack else exp(decay * (time - attack))
                val phase = 2 * PI * f * time
                val tri = 2 / PI * kotlin.math.asin(sin(2 * phase))
                val idx = start + i
                if (idx < total) out[idx] += volume * env * (sin(phase) + 0.18 * tri)
            }
        }
        return ShortArray(total) { (out[it].coerceIn(-1.0, 1.0) * Short.MAX_VALUE).toInt().toShort() }
    }

    private fun play(context: Context, key: String, make: () -> ShortArray) {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        if (audio.ringerMode != AudioManager.RINGER_MODE_NORMAL) return
        runCatching {
            val pcm = cache.getOrPut(key, make)
            val track = AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(RATE).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                .setBufferSizeInBytes(pcm.size * 2).setTransferMode(AudioTrack.MODE_STATIC).build()
            track.write(pcm, 0, pcm.size)
            track.play()
            main.postDelayed({ runCatching { track.stop(); track.release() } }, pcm.size * 1000L / RATE + 150)
        }
    }
}

/** The context for SprintSound in a composable. */
@Composable
fun rememberSoundContext(): Context = LocalContext.current.applicationContext
