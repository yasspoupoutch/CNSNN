package com.poupoutch.cnsnn.ui

import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import com.poupoutch.cnsnn.core.WordEngine

/**
 * The board's letters: the consonants, or the word with its vowels placed (`gold`). An expression goes on two or
 * three lines, cut between its words (WordEngine.lines), and the letters shrink only when a line still does not fit
 * the width: the whole board always shows, never cut (« Qu’est-ce qu’on a fait au Bon Dieu », Galaxy S9 included).
 * `size` is the size of a short board on one line (already fitted to the height, see fitConsonants).
 */
@Composable
fun BoardLetters(text: String, size: Int, modifier: Modifier = Modifier, gold: Boolean = false, letterSpacing: TextUnit = 3.sp) {
    val lines = remember(text) { WordEngine.lines(text) }
    val shown = lines.joinToString("\n")
    val start = if (lines.size > 1) minOf(size, 50) else size
    BoxWithConstraints(modifier, contentAlignment = Alignment.Center) {
        val fitted = fitToWidth(shown, Type.serif(start).copy(letterSpacing = letterSpacing), constraints.maxWidth)
        Text(if (gold) highlighted(shown) else AnnotatedString(shown), style = Type.serif(fitted), letterSpacing = letterSpacing,
            textAlign = TextAlign.Center, maxLines = lines.size, softWrap = false)
    }
}

/**
 * The largest whole size, up to the style's, at which `text` (one or more lines, no wrapping) fits `maxWidth` px,
 * and not under `min` sp.
 */
@Composable
internal fun fitToWidth(text: String, style: TextStyle, maxWidth: Int, min: Int = 12): Int {
    val start = style.fontSize.value.toInt()
    val measurer = rememberTextMeasurer()
    return remember(text, style, maxWidth) {
        if (maxWidth <= 0 || maxWidth == Int.MAX_VALUE) return@remember start
        val width = measurer.measure(text, style, softWrap = false).size.width
        if (width <= maxWidth) start
        // The letter spacing does not shrink with the letters: a little margin so the last one never drops.
        else (start * maxWidth * 0.96f / width).toInt().coerceIn(min, start)
    }
}
