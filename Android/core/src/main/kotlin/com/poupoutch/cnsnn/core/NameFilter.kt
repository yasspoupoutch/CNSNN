package com.poupoutch.cnsnn.core

import java.text.Normalizer

/**
 * Refuses offensive pseudos. Same lists as Core/NameFilter.swift and firestore.rules `cleanName`,
 * so a modified app cannot publish one either.
 */
object NameFilter {
    private val anywhere = listOf(
        "putain", "salope", "salaud", "encul", "niquer", "niquetamere", "niktamer", "connard", "connasse", "conasse",
        "batard", "merde", "couille", "pedophile", "pedo", "hitler", "negre", "bougnoul", "youpin", "bicot",
        "tapette", "tafiole", "gouine", "porno", "sexe", "fuck", "shit", "bitch", "cunt", "nigg", "whore", "slut",
        "enfoir", "filsdepute", "fdp", "daech",
    )
    /** Refused only as the whole pseudo: too common inside ordinary names (Computer, Monique, Nazim). */
    private val whole = setOf("pute", "lapute", "con", "lecon", "nazi", "bite", "pd", "ntm", "nique", "pede", "viol", "suce", "sucemoi")
    private val leet = mapOf('0' to 'o', '1' to 'i', '3' to 'e', '4' to 'a', '5' to 's', '7' to 't', '@' to 'a', '$' to 's')

    /** The pseudo a new player gets at first launch, until they choose one in Profil ("Joueur4821"). */
    fun automatic(): String = "Joueur" + (1000..99999).random()
    /** True for a pseudo given automatically: the player has not chosen one yet. */
    fun isAutomatic(name: String): Boolean = Regex("Joueur[0-9]{4,5}").matches(name)

    fun isAllowed(name: String): Boolean {
        val key = simplified(name)
        return key !in whole && anywhere.none { key.contains(it) }
    }
    internal fun simplified(name: String): String =
        Normalizer.normalize(name, Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "").lowercase()
            .mapNotNull { leet[it] ?: it.takeIf { c -> c in 'a'..'z' } }.joinToString("")
}
