package com.poupoutch.cnsnn

import android.app.Application
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.poupoutch.cnsnn.reminders.ChallengeWatch
import com.poupoutch.cnsnn.reminders.Reminders

class CnsnnApp : Application() {
    override fun onCreate() {
        super.onCreate()
        val host = BuildConfig.EMULATOR_HOST
        if (host.isNotEmpty()) Cloud.useEmulators(this, host)
        Reminders.createChannel(this)
        ChallengeWatch.createChannel(this)
    }
}

/** The Firebase project the app talks to: the real one, or the local emulators in test builds. */
object Cloud {
    var app: FirebaseApp? = null; private set
    val auth: FirebaseAuth get() = app?.let { FirebaseAuth.getInstance(it) } ?: FirebaseAuth.getInstance()
    val db: FirebaseFirestore get() = app?.let { FirebaseFirestore.getInstance(it) } ?: FirebaseFirestore.getInstance()

    /** Test builds only: a "demo-" project that exists only in the emulators, which enforce the real rules. */
    fun useEmulators(context: android.content.Context, host: String) {
        val options = FirebaseOptions.Builder().setProjectId("demo-cnsnn").setApplicationId("1:1:android:1").setApiKey("demo-key").build()
        val emulator = FirebaseApp.getApps(context).firstOrNull { it.name == "emulator" } ?: FirebaseApp.initializeApp(context, options, "emulator").also {
            FirebaseAuth.getInstance(it).useEmulator(host, 9099)
            FirebaseFirestore.getInstance(it).useEmulator(host, 8080)
        }
        app = emulator
    }
}
