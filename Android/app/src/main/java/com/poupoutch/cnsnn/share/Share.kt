package com.poupoutch.cnsnn.share

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import androidx.core.content.FileProvider
import androidx.core.content.res.ResourcesCompat
import com.poupoutch.cnsnn.R
import com.poupoutch.cnsnn.core.Attempt
import com.poupoutch.cnsnn.core.Card
import com.poupoutch.cnsnn.core.DailySchedule
import com.poupoutch.cnsnn.core.Format
import com.poupoutch.cnsnn.core.GameMode
import com.poupoutch.cnsnn.core.Site
import com.poupoutch.cnsnn.core.WordEngine
import java.io.File

/** Shares a result as a picture (only the consonants, no spoiler) with its text, or as text alone. */
object Share {
    fun text(attempt: Attempt, card: Card?, mode: GameMode): String {
        val outcome = if (attempt.correct) "trouvé en ${Format.clock(attempt.timeMs)} · +${attempt.points} pts" else "raté"
        val title = if (mode == GameMode.DAILY) "Mot du jour ${attempt.dailyKey ?: DailySchedule.key(attempt.date)}" else "Classique"
        return "CNSNN · $title : $outcome" + (card?.let { "\n" + it.wordNoVowels } ?: "") + "\nJouez aussi : ${Site.URL}"
    }

    fun result(context: Context, attempt: Attempt, card: Card?, mode: GameMode) {
        val text = text(attempt, card, mode)
        val intent = Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_TEXT, text)
        val image = card?.let { runCatching { image(context, attempt, it, mode) }.getOrNull() }
        if (image != null) {
            val uri = FileProvider.getUriForFile(context, context.packageName + ".files", image)
            intent.setType("image/png").putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            intent.clipData = ClipData.newRawUri(null, uri)
        } else intent.setType("text/plain")
        context.startActivity(Intent.createChooser(intent, null))
    }

    private fun image(context: Context, attempt: Attempt, card: Card, mode: GameMode): File {
        val w = 1080; val h = 1350
        val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.shader = LinearGradient(0f, 0f, 0f, h.toFloat(), 0xFF121426.toInt(), 0xFF06070C.toInt(), Shader.TileMode.CLAMP)
        canvas.drawRect(0f, 0f, w.toFloat(), h.toFloat(), paint)
        paint.shader = null
        val wordmark = ResourcesCompat.getFont(context, R.font.fraunces_black) ?: Typeface.DEFAULT_BOLD
        val serif = ResourcesCompat.getFont(context, R.font.instrument_serif) ?: Typeface.SERIF
        val italic = ResourcesCompat.getFont(context, R.font.instrument_serif_italic) ?: Typeface.SERIF
        val gold = 0xFFFFC65A.toInt(); val white = 0xFFF4F5F8.toInt(); val grey = 0xA3F4F5F8.toInt(); val mint = 0xFF5AE6C6.toInt()

        // Wordmark with gold vowels.
        paint.typeface = wordmark; paint.textSize = 90f
        val mark = "CONSONNE"
        var x = (w - paint.measureText(mark)) / 2
        for (c in mark) { paint.color = if (WordEngine.isVowel(c)) gold else white; canvas.drawText(c.toString(), x, 190f, paint); x += paint.measureText(c.toString()) }

        fun centered(text: String, y: Float, size: Float, face: Typeface, color: Int, spacing: Float = 0f) {
            paint.typeface = face; paint.textSize = size; paint.color = color; paint.letterSpacing = spacing
            while (paint.measureText(text) > w - 140 && paint.textSize > 30) paint.textSize -= 4
            canvas.drawText(text, (w - paint.measureText(text)) / 2, y, paint)
            paint.letterSpacing = 0f
        }
        val title = if (mode == GameMode.DAILY) "MOT DU JOUR · " + (attempt.dailyKey ?: DailySchedule.key(attempt.date)) else "CLASSIQUE"
        centered(title, 270f, 38f, Typeface.DEFAULT_BOLD, grey, 0.12f)
        centered(card.wordNoVowels, 690f, 230f, serif, white, 0.08f)
        paint.color = gold
        canvas.drawRoundRect(RectF(w / 2f - 66, 760f, w / 2f + 66, 772f), 6f, 6f, paint)
        val outcome = if (attempt.correct) "Trouvé en ${Format.clock(attempt.timeMs)} · +${attempt.points} pts" else "Raté cette fois"
        centered(outcome, 880f, 62f, Typeface.create(Typeface.DEFAULT, Typeface.BOLD), if (attempt.correct) mint else grey)
        centered("Trouverez-vous les voyelles ?", 1200f, 66f, italic, gold)

        val dir = File(context.cacheDir, "share").apply { mkdirs() }
        val file = File(dir, "cnsnn.png")
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
        return file
    }
}
