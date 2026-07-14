package com.facundopri.tetherpane.companion

import android.content.Context
import android.content.Intent
import android.provider.Settings

fun interface DeveloperSettingsNavigator {
    fun openDeveloperOptions()
}

class ContextDeveloperSettingsNavigator(
    private val context: Context,
) : DeveloperSettingsNavigator {
    override fun openDeveloperOptions() {
        val intent = Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }
}
