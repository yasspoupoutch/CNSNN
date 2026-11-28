package com.poupoutch.cnsnn.core

import java.text.Normalizer

object WordEngine {
    /** French editorial convention: accents dropped, Œ and Æ expanded, letters only, Y is a vowel. */
    fun normalize(value: String): String {
        val expanded = value.replace("œ", "oe").replace("Œ", "OE").replace("æ", "ae").replace("Æ", "AE")
        return Normalizer.normalize(expanded, Normalizer.Form.NFD)
            .replace(Regex("\\p{M}+"), "")
            .uppercase(java.util.Locale.FRENCH)
            .filter { it in 'A'..'Z' }
    }
    fun consonants(value: String): String = normalize(value).filter { it !in "AEIOUY" }
    /** The vowels of the word, each once, in alphabetical order: the first hint lights them up on the keyboard. */
    fun vowels(value: String): String {
        val present = normalize(value).filter { it in "AEIOUY" }.toSet()
        return "AEIOUY".filter { it in present }
    }
    /** The hints after the sentence place the word's vowels one by one, in order (ŒUVRE: OVR, OEVR, OEUVR).
     *  `letters` counts the vowels; the last one is the word itself, revealed at the end, so the steps stop
     *  one before (same as Core/WordEngine.swift and Firebase/tools/daily.mjs placedVowels). */
    data class Placed(val letters: Int, val steps: List<String>)
    fun placedVowels(value: String): Placed {
        val letters = normalize(value)
        val total = letters.count { it in "AEIOUY" }
        // An expression keeps its words apart, like the board (« QUST C QN – FT – BN DN »), so it can go on several lines.
        val words = boardWords(value)
        val steps = (1 until total).map { k ->
            var seen = 0
            if (words.size <= 1) letters.filter { c -> c !in "AEIOUY" || ++seen <= k }
            else words.joinToString(" ") { word -> normalize(word).filter { c -> c !in "AEIOUY" || ++seen <= k }.ifEmpty { "–" } }
        }
        return Placed(maxOf(total, 1), steps)
    }
    private fun boardWords(value: String) = value.split(Regex("[\\s\\-‐‑–—]+")).filter { normalize(it).isNotEmpty() }
    /**
     * A board (or an expression) cut on its spaces into as few lines as possible, at most `maxLines`, each line
     * `maxChars` long at most when it can be, the lines as even as they can be. A single word stays on one line
     * (the screen shrinks it instead). « QST C QN – FT – BN DN » is « QST C QN », « – FT – », « BN DN ».
     */
    fun lines(text: String, maxChars: Int = 10, maxLines: Int = 3): List<String> {
        val words = text.split(" ").filter { it.isNotEmpty() }
        if (words.size <= 1 || text.length <= maxChars) return listOf(text)
        fun cuts(start: Int, left: Int): List<List<Int>> =
            if (left == 1) listOf(emptyList())
            else (start + 1..words.size - left + 1).flatMap { cut -> cuts(cut, left - 1).map { listOf(cut) + it } }
        var best = listOf(text)
        // Every way to cut the words into n lines, from one line up: the first n whose lines all fit wins,
        // the most even one among them; if none fits, the most even with the most lines allowed.
        for (n in 1..minOf(maxLines, words.size)) {
            var bestWidest = Int.MAX_VALUE
            for (cut in cuts(0, n)) {
                val bounds = listOf(0) + cut + words.size
                val split = bounds.zipWithNext { a, b -> words.subList(a, b).joinToString(" ") }
                val widest = split.maxOf { it.length }
                if (widest < bestWidest) { best = split; bestWidest = widest }
            }
            if (bestWidest <= maxChars) break
        }
        return best
    }
    /** What the board shows: the consonants of each word, a space between words (a hyphen splits them too), a dash for a word
     *  with no consonant (« Où est Charlie » is « – ST CHRL »). A single word is just its consonants. */
    fun shownConsonants(value: String): String {
        val words = boardWords(value)
        if (words.size <= 1) return consonants(value)
        return words.joinToString(" ") { consonants(it).ifEmpty { "–" } }
    }
    /** The board read aloud: letters apart, words apart. */
    fun spoken(shown: String): String = shown.split(" ").joinToString(" ; ") { it.toList().joinToString(", ") }
    fun matches(answer: String, word: String): Boolean {
        val normalized = normalize(answer)
        return normalized.isNotEmpty() && normalized == normalize(word)
    }
    fun validWord(word: String): Boolean = normalize(word).length in 3..40 && consonants(word).isNotEmpty()
    /** A letter shown in gold: A E I O U Y with or without accents, and Œ Æ. */
    fun isVowel(character: Char): Boolean {
        if (character in "ŒÆœæ") return true
        return normalize(character.toString()).let { it.isNotEmpty() && it.all { c -> c in "AEIOUY" } }
    }
}

/**
 * The answer being typed, with its caret (same rules as TypedAnswer in Core/WordEngine.swift): letters go
 * in at the caret, ⌫ erases the letter before it, and a slide on the space bar or on the answer moves it.
 * `cursor` counts the characters before the caret; null keeps it at the end, where typing normally happens.
 */
data class TypedAnswer(val text: String, val cursor: Int? = null) {
    /** Where the caret really is, even after the text was replaced behind its back. */
    val position: Int get() = (cursor ?: text.length).coerceIn(0, text.length)
    val before: String get() = text.take(position)
    val after: String get() = text.drop(position)
    /** The caret's place when it sits inside the text, null when it is at the end. */
    val inside: Int? get() = position.takeIf { it < text.length }

    /** No space at the start or next to another space, and 40 characters at most. */
    fun insert(letter: String): TypedAnswer {
        if (text.length + letter.length > MAX_LENGTH) return this
        if (letter == " " && (before.isEmpty() || before.endsWith(" ") || after.startsWith(" "))) return this
        return TypedAnswer(before + letter + after).place(position + letter.length)
    }

    fun deleteBackward(): TypedAnswer {
        val at = position
        if (at == 0) return this
        return TypedAnswer(text.take(at - 1) + after).place(at - 1)
    }

    /** Moves the caret by a number of characters, staying inside the text. */
    fun move(steps: Int): TypedAnswer = place(position + steps)

    /** Puts the caret before character [index] (0 = start); past the end means at the end. */
    fun place(index: Int): TypedAnswer {
        val clamped = index.coerceIn(0, text.length)
        return copy(cursor = if (clamped == text.length) null else clamped)
    }

    companion object { const val MAX_LENGTH = 40 }
}
