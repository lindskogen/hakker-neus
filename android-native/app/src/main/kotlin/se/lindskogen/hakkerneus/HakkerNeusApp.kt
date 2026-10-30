package se.lindskogen.hakkerneus

import android.app.Application

class HakkerNeusApp : Application() {
    override fun onCreate() {
        super.onCreate()
        AppContainer.init(this)
    }
}
