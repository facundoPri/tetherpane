package com.facundopri.tetherpane.companion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class OnboardingUiStateTest {
    @Test
    fun onboardingOffersDeveloperSettingsWithoutClaimingItCanAuthorizeAdb() {
        val state = OnboardingUiState.initial()

        assertEquals("Open Developer options", state.primaryActionLabel)
        assertEquals(
            listOf(
                "Enable Developer options and turn on Wireless Debugging.",
                "On the Mac, select this phone under Nearby over Wi-Fi and choose Pair with code.",
                "On this phone, open Wireless Debugging and choose Pair device with pairing code.",
                "Enter the six-digit code shown here into the Mac app. No USB cable is required.",
            ),
            state.steps,
        )
        assertFalse(state.description.contains("scan the QR", ignoreCase = true))
        assertFalse(state.description.contains("grant ADB", ignoreCase = true))
        assertFalse(state.description.contains("authorize scrcpy", ignoreCase = true))
    }
}
