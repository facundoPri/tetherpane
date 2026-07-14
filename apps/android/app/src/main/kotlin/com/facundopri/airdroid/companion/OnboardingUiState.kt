package com.facundopri.airdroid.companion

data class OnboardingUiState(
    val title: String,
    val description: String,
    val primaryActionLabel: String,
    val steps: List<String>,
) {
    companion object {
        fun initial() = OnboardingUiState(
            title = "Set up Wireless Debugging",
            description = "Pair this phone with the Mac once using Android's six-digit Wireless Debugging code. The regular Camera app treats ADB QR codes like Wi-Fi networks, so code pairing is the reliable setup path.",
            primaryActionLabel = "Open Developer options",
            steps = listOf(
                "Enable Developer options and turn on Wireless Debugging.",
                "On the Mac, select this phone under Nearby over Wi-Fi and choose Pair with code.",
                "On this phone, open Wireless Debugging and choose Pair device with pairing code.",
                "Enter the six-digit code shown here into the Mac app. No USB cable is required.",
            ),
        )
    }
}
