package com.facundopri.tetherpane.companion

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface {
                    OnboardingScreen(
                        state = OnboardingUiState.initial(),
                        onOpenDeveloperOptions = ContextDeveloperSettingsNavigator(this)::openDeveloperOptions,
                    )
                }
            }
        }
    }
}
