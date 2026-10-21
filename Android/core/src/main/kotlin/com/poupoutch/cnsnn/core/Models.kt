package com.poupoutch.cnsnn.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import java.time.Instant
import java.util.UUID

// The progress is stored as JSON in Firestore (users/{uid}/private/progress) and read by the
// iPhone app too, so every type below encodes exactly like its Swift Codable twin (Core/Models.swift).

@Serializable
enum class Category(val label: String) {
    @SerialName("Général") GENERAL("Général"),
    @SerialName("Football") FOOTBALL("Football"),
    @SerialName("Cinéma") CINEMA("Cinéma"),
    @SerialName("Géographie") GEOGRAPHY("Géographie"),
    @SerialName("Animaux") ANIMALS("Animaux"),
    @SerialName("Objets") OBJECTS("Objets");

    companion object {
        fun of(label: String?): Category? = entries.firstOrNull { it.label == label }
    }
}

@Serializable
enum class Difficulty(val label: String) {
    @SerialName("Facile") EASY("Facile"),
    @SerialName("Moyen") MEDIUM("Moyen"),
    @SerialName("Difficile") HARD("Difficile");

    companion object {
        fun of(label: String?): Difficulty? = entries.firstOrNull { it.label == label }
    }
}

@Serializable
enum class GameMode { @SerialName("classic") CLASSIC, @SerialName("daily") DAILY }

@Serializable
enum class ReviewStatus { @SerialName("pending") PENDING, @SerialName("approved") APPROVED, @SerialName("rejected") REJECTED }

/** Swift's default Date encoding: seconds since 2001-01-01T00:00:00Z, as a number. */
object AppleDateSerializer : KSerializer<Instant> {
    private const val REFERENCE = 978_307_200L
    override val descriptor = PrimitiveSerialDescriptor("AppleDate", PrimitiveKind.DOUBLE)
    override fun serialize(encoder: Encoder, value: Instant) =
        encoder.encodeDouble((value.toEpochMilli() - REFERENCE * 1000) / 1000.0)
    override fun deserialize(decoder: Decoder): Instant =
        Instant.ofEpochMilli(Math.round(decoder.decodeDouble() * 1000) + REFERENCE * 1000)
}

@Serializable
data class Card(
    val id: String,
    val wordFull: String,
    val hint: String,
    val category: Category,
    val difficulty: Difficulty,
    val status: ReviewStatus = ReviewStatus.APPROVED,
    /** Pseudo of the player who proposed a community card (null for built-in cards). */
    val author: String? = null,
    /** Consonants given by the server for a secret Mot du jour, whose word stays unknown until the end. */
    val masked: String? = null,
) {
    val wordNoVowels: String get() = masked ?: WordEngine.shownConsonants(wordFull)
}

@Serializable
data class Attempt(
    val id: String = UUID.randomUUID().toString().uppercase(),
    val cardID: String,
    val mode: GameMode,
    val correct: Boolean,
    val timeMs: Int,
    /** Points of the old scoring, kept to read old saves; new attempts store 0 and nothing shows them. */
    val points: Int = 0,
    @Serializable(with = AppleDateSerializer::class) val date: Instant,
    val dailyKey: String? = null,
)

@Serializable
data class Submission(
    val id: String = UUID.randomUUID().toString().uppercase(),
    val card: Card,
    @Serializable(with = AppleDateSerializer::class) val createdAt: Instant = Instant.now(),
) {
    /** The proposed word, normalized: the same card id on every device and on the server. */
    val word: String get() = WordEngine.normalize(card.wordFull)
}

@Serializable
data class Progress(
    val username: String = "",
    val attempts: List<Attempt> = emptyList(),
    val recentCards: List<String> = emptyList(),
    val submissions: List<Submission> = emptyList(),
    val dailyStarted: Map<String, String> = emptyMap(),
    val dailyStartedAt: Map<String, @Serializable(with = AppleDateSerializer::class) Instant> = emptyMap(),
    /** Secret Mot du jour words, revealed by the server once the day's game is over (by day key). */
    val dailyWords: Map<String, Card>? = null,
    /** Version of the community rules this player accepted (CommunityRules.VERSION), null before any. */
    val rulesVersion: Int? = null,
    /** Personal records of Sprint, Survie and Double sens (by PlayMode key). Never official. */
    val modes: Map<String, ModeRecords>? = null,
) {
    val correctAnswers: Int get() = attempts.count { it.correct }
    /** Level from the words found (no more points): 20 words per level. */
    val level: Int get() = ClassicLevel.level(correctAnswers)
    val levelInto: Int get() = ClassicLevel.into(correctAnswers)
    val successRate: Double get() = if (attempts.isEmpty()) 0.0 else correctAnswers.toDouble() / attempts.size
    val bestTimeMs: Int? get() = attempts.filter { it.correct }.minOfOrNull { it.timeMs }
    val averageTimeMs: Int? get() = attempts.filter { it.correct }.takeIf { it.isNotEmpty() }?.let { wins -> wins.sumOf { it.timeMs } / wins.size }
    val dailyWins: Int get() = attempts.count { it.mode == GameMode.DAILY && it.correct }

    /** Daily words found in a row, up to today (or yesterday while today is not played yet). */
    fun streak(at: Instant = Instant.now()): Int {
        val days = attempts.filter { it.mode == GameMode.DAILY && it.correct }.mapNotNull { it.dailyKey }.toSet()
        var current = DailySchedule.key(at)
        if (current !in days) current = DailySchedule.shift(current, -1)
        var count = 0
        while (current in days) { count++; current = DailySchedule.shift(current, -1) }
        return count
    }

    /**
     * Combines two copies of the same player's progress (this device and the cloud).
     * History only grows: attempts are united by id, and a day keeps a single daily result.
     */
    fun merged(other: Progress): Progress {
        val ids = attempts.map { it.id }.toMutableSet()
        val days = attempts.mapNotNull { it.dailyKey }.toMutableSet()
        val all = attempts.toMutableList()
        for (attempt in other.attempts) {
            if (attempt.id in ids) continue
            val day = attempt.dailyKey
            if (day != null) { if (day in days) continue; days += day }
            ids += attempt.id
            all += attempt
        }
        val words = when {
            other.dailyWords == null -> dailyWords
            else -> (dailyWords ?: emptyMap()).toMutableMap().also { mine ->
                for ((day, card) in other.dailyWords) {
                    val known = mine[day]
                    if (known == null || known.wordFull.isEmpty()) mine[day] = card
                }
            }
        }
        // One proposal per word: the reviewed copy wins over a pending one, otherwise this device's.
        val proposals = LinkedHashMap<String, Submission>()
        for (submission in submissions) proposals.putIfAbsent(submission.word, submission)
        for (submission in other.submissions) {
            val known = proposals[submission.word]
            if (known == null || (known.card.status == ReviewStatus.PENDING && submission.card.status != ReviewStatus.PENDING)) proposals[submission.word] = submission
        }
        val rules = listOfNotNull(rulesVersion, other.rulesVersion).maxOrNull()
        val records = if (other.modes == null) modes else (modes ?: emptyMap()).toMutableMap().also { mine ->
            for ((mode, theirs) in other.modes) mine[mode] = (mine[mode] ?: ModeRecords()).merged(theirs)
        }
        return copy(
            username = username.ifEmpty { other.username },
            attempts = all.sortedBy { it.date },
            dailyStarted = other.dailyStarted + dailyStarted,
            dailyStartedAt = other.dailyStartedAt + dailyStartedAt,
            dailyWords = words,
            submissions = proposals.values.toList(),
            recentCards = recentCards.ifEmpty { other.recentCards },
            rulesVersion = rules,
            modes = records,
        )
    }

    fun toJson(): String = ProgressJson.encodeToString(serializer(), this)

    companion object {
        fun fromJson(json: String): Progress = ProgressJson.decodeFromString(serializer(), json)
    }
}

/** Every key written (the Swift decoder requires them), nulls left out (Swift optionals). */
val ProgressJson = Json {
    encodeDefaults = true
    explicitNulls = false
    ignoreUnknownKeys = true
}
