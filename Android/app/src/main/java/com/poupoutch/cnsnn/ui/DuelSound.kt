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
 * A short bright "gling" when a live duel finds its opponent. Made in code (no sound file), the same two
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

    /** 0.6 s, mono 16 bits: E6 then B6 a moment later, each fading out like a small bell. */
    fun samples(): ShortArray {
        val count = RATE * 6 / 10
        return ShortArray(count) { i ->
            val t = i.toDouble() / RATE
            fun bell(freq: Double, start: Double): Double {
                val u = t - start
                if (u < 0) return 0.0
                val attack = min(1.0, u / 0.004)
                return attack * exp(-u / 0.16) * (sin(2 * PI * freq * u) + 0.25 * sin(4 * PI * freq * u))
            }
            val v = 0.32 * (bell(1318.5, 0.0) + bell(1975.5, 0.09))
            (v.coerceIn(-1.0, 1.0) * 32_000).toInt().toShort()
        }
    }
}
