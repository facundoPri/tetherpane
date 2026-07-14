# AirDroid scrcpy spike

This is a native macOS/Android monorepo spike. The macOS control center is SwiftUI and launches the stock, separately-windowed `scrcpy` 4.1 client. The Android companion is Kotlin/Compose onboarding and status UI; it **cannot** grant, replace, or silently authorize ADB.

`AirDroid` is an internal codename only. This repository deliberately excludes an embedded video renderer, a scrcpy protocol implementation, distribution packaging, signing, notarization, and public-release naming work.

## Developer commands

| Command | Purpose |
| --- | --- |
| `make doctor` | Read-only toolchain, Android SDK, ADB, device, and scrcpy report. |
| `make bootstrap` | Install the JDK and Android command-line tools if needed, then interactively accept Android SDK licenses and install the pinned SDK packages. |
| `make test` | Run the macOS contract runner and Android unit tests. |
| `make macos-build` | Build the SwiftPM package. |
| `make macos-test` | Run deterministic macOS domain/adapter seam contracts. |
| `make macos-run` | Build and launch the foreground macOS `.app`. |
| `make android-build` | Assemble the Android debug APK through the checked-in Gradle wrapper. |
| `make android-test` | Run Android local unit tests. |
| `make android-install [SERIAL=<serial>]` | Install and launch on exactly one authorized device, or the explicit serial. |
| `make android-qa [SERIAL=<serial>]` | Install, launch, inspect UI-tree-derived onboarding interaction, capture a screenshot, and save bounded logcat. |
| `make android-emulator` | Optionally create/start the pinned Apple-silicon API 36 AVD. |

`make bootstrap` intentionally requires a terminal when Android licenses need approval. It never accepts licenses silently or changes shell profiles. All Android commands resolve a JDK 17 and SDK root for the process only.

`make android-emulator` enables Developer options only inside its disposable AVD, so the QA script can verify the companion's settings action after the app's documented first step. It never changes a connected physical device's Developer options or ADB authorization.

## Cable-free Wireless Debugging

The normal Wi-Fi flow does not require an initial USB connection. Stock scrcpy uses ADB, so Android must still authorize this Mac once through the system Wireless Debugging UI; merely sharing an SSID is not sufficient for first-time trust.

1. Put the Mac and Android device on the same Wi-Fi network.
2. On Android, enable Developer options and turn on **Wireless debugging**.
3. In the Mac control center, select the phone under **Nearby over Wi-Fi**. This row comes from ADB mDNS discovery and appears before the phone is authorized.
4. On Android, choose **Pair device with pairing code** and keep the six-digit dialog open.
5. Enter that code in the Mac app and choose **Pair and connect over Wi-Fi**.
6. The Mac pairs through stock `adb`, connects the separate connection endpoint for that exact phone, verifies the authorized wireless serial, and promotes it to a **Wi-Fi** device in the sidebar.

Pairing codes are sent to `adb` through standard input, never placed in process arguments, logged, or persisted. The app rediscovers dynamic ports instead of saving them as device identity.

QR remains a secondary option. Generate it on the Mac, then scan it only through **Wireless debugging → Pair device with QR code**. Do not use the regular Camera app, Google Lens, or the AirDroid companion: the ADB payload intentionally uses a `WIFI:` envelope, so a generic scanner may try to configure a network and cannot invoke Android's privileged ADB pairing service. Guest/corporate Wi-Fi may also block mDNS or isolate devices; both devices must be on a LAN that permits peer discovery and traffic.

See [Stock scrcpy 4.1 over Android Wireless Debugging](docs/research/stock-scrcpy-wireless-debugging.md) for the primary-source protocol and platform constraints.

## Layout

```text
apps/android/                 Kotlin/Compose companion and Gradle wrapper
Sources/AirDroidDomain/       typed devices and session configuration
Sources/AirDroidScrcpy/       scrcpy argument and process adapter seam
Sources/AirDroidMac/          SwiftUI control center
Sources/AirDroidMacSeamTests/ deterministic Swift seam test runner
engines/scrcpy/               pin and compatibility note
script/                       stable developer command implementations
```

## Pinned spike toolchain

- scrcpy: 4.1 (external local developer tool; not bundled)
- Android Gradle Plugin: 9.2.1
- Gradle wrapper: 9.4.1
- JDK: 17
- Kotlin/Compose compiler plugin: 2.3.21
- Compose BOM: 2026.06.00
- compile/target SDK: 36; min SDK: 30; Build Tools: 36.0.0

The Android versions are compatibility-first: AGP 9.2 requires Gradle 9.4.1+, Build Tools 36.0.0, and JDK 17; Kotlin 2.3.21 is the version in Android's current AGP/Compose setup examples. Kotlin 2.4.0 is newer, but its published compatibility table does not yet list AGP 9.2.

## Testing seams

Tests cross only these public seams: `DeviceDiscovery`, `PairingClient`, `WirelessConnectionClient`, `WirelessQRCodePairingSession`, `MirroringEngine`, `ScrcpyCommandBuilder`, Android onboarding/settings, and the root command interface. System process, binary lookup, filesystem, and Android settings adapters are the true system edges; views consume typed state, not raw command output.

The active Command Line Tools-only Swift toolchain does not expose XCTest or Swift Testing, so the Swift seam contracts are a SwiftPM executable (`AirDroidMacSeamTests`) run by `make macos-test`. This is a real failing-process contract runner, not a zero-test `swift test` result.
