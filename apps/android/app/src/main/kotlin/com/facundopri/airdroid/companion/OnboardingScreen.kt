package com.facundopri.tetherpane.companion

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp

@Composable
@OptIn(ExperimentalMaterial3Api::class)
fun OnboardingScreen(
    state: OnboardingUiState,
    onOpenDeveloperOptions: () -> Unit,
) {
    Scaffold(
        topBar = { TopAppBar(title = { Text("TetherPane Companion") }) },
    ) { contentPadding ->
        OnboardingContent(
            state = state,
            contentPadding = contentPadding,
            onOpenDeveloperOptions = onOpenDeveloperOptions,
        )
    }
}

@Composable
private fun OnboardingContent(
    state: OnboardingUiState,
    contentPadding: PaddingValues,
    onOpenDeveloperOptions: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(contentPadding)
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(state.title, style = MaterialTheme.typography.headlineSmall)
        Text(state.description, style = MaterialTheme.typography.bodyLarge)

        Text("On this phone", style = MaterialTheme.typography.titleMedium)
        state.steps.forEachIndexed { index, step ->
            Text("${index + 1}. $step")
        }

        Button(
            onClick = onOpenDeveloperOptions,
            modifier = Modifier
                .fillMaxWidth()
                .testTag("open-developer-options"),
        ) {
            Text(state.primaryActionLabel)
        }

        Text(
            "The Mac app discovers ADB devices and starts stock scrcpy. It never receives an Android permission that authorizes ADB on its own.",
            style = MaterialTheme.typography.bodyMedium,
        )
    }
}
