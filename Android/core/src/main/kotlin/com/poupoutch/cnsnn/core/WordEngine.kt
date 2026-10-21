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
    /** What the board shows: the consonants of each word, a space between words, a dash for a word
     *  with no consonant (« Où est Charlie » is « – ST CHRL »). A single word is just its consonants. */
    fun shownConsonants(value: String): String {
        val words = value.split(Regex("\\s+")).filter { normalize(it).isNotEmpty() }
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
