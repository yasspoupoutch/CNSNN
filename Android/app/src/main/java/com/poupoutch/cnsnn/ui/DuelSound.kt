package com.poupoutch.cnsnn.ui

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.min
import kotlin.math.sin

/**
 * A short "match found" chime when a live duel finds its opponent. Made in code (no sound file), the same
 * notes as on the iPhone (DuelSound in Theme.swift). Silent when the phone is on vibrate or silent.
 */
object DuelSound {
    private const val RATE = 44_100

    fun found(context: Context) {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        if (audio.ringerMode != AudioManager.RINGER_MODE_NORMAL) return
        runCatching {
            val pcm = samples()
            val track = AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                .setTransferMode(AudioTrack.MODE_STATIC)
                .setBufferSizeInBytes(pcm.size * 2)
                .build()
            track.write(pcm, 0, pcm.size)
            track.setVolume(0.8f)
            track.notificationMarkerPosition = pcm.size
            track.setPlaybackPositionUpdateListener(object : AudioTrack.OnPlaybackPositionUpdateListener {
                override fun onMarkerReached(t: AudioTrack) { t.release() }
                override fun onPeriodicNotification(t: AudioTrack) {}
            })
            track.play()
        }
    }

    /** 1.1 s, mono 16 bits: a quick rising arpeggio (G5 C6 E6 G6) landing on a bright G6 + C7 chord that
     *  rings out, like the "game found" sounds of online games (an original sound). Same as the iPhone. */
    private val notes = listOf(Triple(783.99, 0.0, 0.10), Triple(1046.5, 0.07, 0.10), Triple(1318.5, 0.14, 0.10),
        Triple(1567.98, 0.21, 0.12), Triple(2093.0, 0.30, 0.38), Triple(1567.98, 0.30, 0.38))

    fun samples(): ShortArray {
        val count = RATE * 11 / 10
        return ShortArray(count) { i ->
            val t = i.toDouble() / RATE
            var v = 0.0
            for ((freq, start, decay) in notes) {
                if (t < start) continue
                val u = t - start
                val w = 2 * PI * freq * u
                v += min(1.0, u / 0.003) * exp(-u / decay) * (sin(w) + 0.3 * sin(2 * w) + 0.1 * sin(3 * w))
            }
            (( v * 0.33).coerceIn(-1.0, 1.0) * 32_000).toInt().toShort()
        }
    }
}
