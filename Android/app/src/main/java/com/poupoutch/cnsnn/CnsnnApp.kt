package com.poupoutch.cnsnn

import android.app.Application
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.poupoutch.cnsnn.reminders.Reminders

class CnsnnApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // Instrumented tests point the app at the Firebase emulators, never at the real project.
        val host = BuildConfig.EMULATOR_HOST
        if (host.isNotEmpty()) {
            FirebaseAuth.getInstance().useEmulator(host, 9099)
            FirebaseFirestore.getInstance().useEmulator(host, 8080)
        }
        Reminders.createChannel(this)
    }
}
