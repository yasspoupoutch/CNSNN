package com.poupoutch.cnsnn.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.poupoutch.cnsnn.R

/** CNSNN's identity (night blue, gold vowels, mint for success) on Material 3. */
object Palette {
    val background = Color(0xFF06070C)
    val backgroundTop = Color(0xFF121426)
    val surface = Color(0xFF17181F)
    val surfaceHigh = Color(0xFF20222B)
    val foreground = Color(0xFFF4F5F8)
    val secondary = foreground.copy(alpha = 0.64f)
    val tertiary = foreground.copy(alpha = 0.56f)
    val line = Color.White.copy(alpha = 0.07f)
    val fill1 = Color.White.copy(alpha = 0.08f)
    val fill2 = Color.White.copy(alpha = 0.14f)
    val border = Color.White.copy(alpha = 0.16f)
    val accent = Color(0xFFFFC65A)
    val accentTop = Color(0xFFFFD573)
    val accentBottom = Color(0xFFF6B84D)
    val onAccent = Color(0xFF1A1406)
    val mint = Color(0xFF5AE6C6)
    val red = Color(0xFFFF8785)
    val redSoft = Color(0x29FD7273)
    val ink = Color(0xFF0B0C10)
    val avatars = listOf(Color(0xFFF3B94C), Color(0xFF49D9B9), Color(0xFFAA99FF), Color(0xFFF28ABD), Color(0xFF5DC0F6))
    fun avatar(index: Int) = avatars[((index % avatars.size) + avatars.size) % avatars.size]
}

object Fonts {
    val serif = FontFamily(Font(R.font.instrument_serif), Font(R.font.instrument_serif_italic, style = FontStyle.Italic))
    val wordmark = FontFamily(Font(R.font.fraunces_black, FontWeight.Black))
}

private val scheme = darkColorScheme(
    primary = Palette.accent, onPrimary = Palette.onAccent,
    primaryContainer = Color(0xFF3A2F14), onPrimaryContainer = Palette.accentTop,
    secondary = Palette.mint, onSecondary = Palette.ink,
    secondaryContainer = Palette.surfaceHigh, onSecondaryContainer = Palette.foreground,
    tertiary = Palette.mint,
    background = Palette.background, onBackground = Palette.foreground,
    surface = Palette.background, onSurface = Palette.foreground,
    surfaceVariant = Palette.surface, onSurfaceVariant = Palette.secondary,
    surfaceContainerLowest = Palette.background, surfaceContainerLow = Color(0xFF101118),
    surfaceContainer = Palette.surface, surfaceContainerHigh = Palette.surfaceHigh, surfaceContainerHighest = Color(0xFF292B35),
    outline = Palette.border, outlineVariant = Palette.line,
    error = Palette.red, onError = Palette.ink, errorContainer = Palette.redSoft, onErrorContainer = Palette.red,
)

private val base = Typography()
private val typography = base.copy(
    displaySmall = base.displaySmall.copy(fontWeight = FontWeight.Bold, letterSpacing = (-0.6).sp),
    headlineLarge = base.headlineLarge.copy(fontWeight = FontWeight.Bold, letterSpacing = (-0.6).sp),
    headlineMedium = base.headlineMedium.copy(fontWeight = FontWeight.Bold, letterSpacing = (-0.4).sp),
    titleLarge = base.titleLarge.copy(fontWeight = FontWeight.Bold),
)

object Type {
    fun serif(size: Int) = TextStyle(fontFamily = Fonts.serif, fontSize = size.sp, lineHeight = (size * 1.1).sp)
    fun serifItalic(size: Int) = TextStyle(fontFamily = Fonts.serif, fontStyle = FontStyle.Italic, fontSize = size.sp, lineHeight = (size * 1.2).sp)
    fun wordmark(size: Int) = TextStyle(fontFamily = Fonts.wordmark, fontWeight = FontWeight.Black, fontSize = size.sp)
    val kicker = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp)
}

@Composable
fun CnsnnTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = scheme, typography = typography, content = content)
}

/** Vowels (Y included), with or without accents, and Œ/Æ. */
fun isVowel(c: Char): Boolean = com.poupoutch.cnsnn.core.WordEngine.isVowel(c)
