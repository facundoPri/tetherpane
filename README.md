# TetherPane

TetherPane is a one-device-first native SwiftUI macOS control center for stock, separately-windowed `scrcpy` 4.1. Connected and saved offline devices remain visible in a native source list; selecting one opens a focused detail with one primary **Mirror** action and route-specific connection management. **Mirroring does not require an Android companion app.** The Kotlin/Compose shell remains in the repository as an optional development artifact, but installing it is not part of either supported connection flow and it cannot grant, replace, or silently authorize ADB.

The public working name is **TetherPane**, the bundle identifier is `com.facundopri.tetherpane`, and the source is available under the [Apache License 2.0](LICENSE). A public downloadable binary still requires a Developer ID Application certificate and Apple notarization. The current beta keeps stock scrcpy and ADB external; see [the dependency decision](docs/SCRCPY_DISTRIBUTION.md).

## Runtime requirements

- macOS 26 or later.
- Stock scrcpy 4.1. The app launches its normal separate SDL window; it does not embed or fork scrcpy.
- Android SDK Platform Tools (`adb`).
- Developer options plus USB debugging or Android Wireless Debugging enabled by the user.

On the first Wi-Fi operation, macOS may ask for Local Network access. Allow it so the app can discover the Android Wireless Debugging services and connect to the phone you selected; denying it leaves direct USB available but blocks Wi-Fi setup until the permission is changed in System Settings.

For the current external-tool beta path, install the two host tools before opening the app. Contributors can use the repository's `Brewfile`; end users can run the two commands directly:

```bash
brew install scrcpy
brew install --cask android-platform-tools
```

```bash
brew bundle --file Brewfile
```

The app looks for explicit `SCRCPY_PATH` / `ADB_PATH` overrides, standard Homebrew locations on Apple silicon and Intel Macs, then the process `PATH`.

## Developer commands

| Command | Purpose |
| --- | --- |
| `make doctor` | Read-only toolchain, Android SDK, ADB, device, and scrcpy report. |
| `make bootstrap` | Install the JDK and Android command-line tools if needed, then interactively accept Android SDK licenses and install the pinned SDK packages. |
| `make test` | Run the macOS contract runner and Android unit tests. |
| `make macos-build` | Build the SwiftPM package. |
| `make macos-test` | Run deterministic macOS domain/adapter seam contracts. |
| `make xcode-project-test` | Validate the shared Xcode app scheme and build it when full Xcode is selected. |
| `make macos-run` | Build and launch the foreground macOS `.app`. |
| `make macos-release VERSION=0.1.0 BUILD_NUMBER=1` | Build a hardened, ad-hoc-signed local release app and versioned ZIP. |
| `make macos-release-test` | Build and independently verify the macOS release-bundle contract. |
| `make android-build` | Assemble the Android debug APK through the checked-in Gradle wrapper. |
| `make android-test` | Run Android local unit tests. |
| `make android-install [SERIAL=<serial>]` | Install and launch on exactly one authorized device, or the explicit serial. |
| `make android-qa [SERIAL=<serial>]` | Install, launch, inspect UI-tree-derived onboarding interaction, capture a screenshot, and save bounded logcat. |
| `make android-emulator` | Optionally create/start the pinned Apple-silicon API 36 AVD. |

`make bootstrap` intentionally requires a terminal when Android licenses need approval. It never accepts licenses silently or changes shell profiles. All Android commands resolve a JDK 17 and SDK root for the process only.

`make android-emulator` enables Developer options only inside its disposable AVD, so the QA script can verify the companion's settings action after the app's documented first step. It never changes a connected physical device's Developer options or ADB authorization.

## Release packaging

`TetherPane.xcodeproj` now owns the native macOS application target, shared scheme, app icon catalog, bundle settings, privacy manifest, hardened runtime, and Archive action. It consumes the existing `AirDroidDomain`, `AirDroidScrcpy`, and isolated `TetherPaneUIFixtureSupport` SwiftPM library products as local package dependencies instead of duplicating those source trees. SwiftPM remains the portable library and seam-test path during the migration.

`script/package_macos.sh` remains the single bundle-staging interface. With full Xcode selected it builds the native `TetherPane` scheme; on a Command Line Tools-only machine it uses the SwiftPM fallback. Both paths inject release metadata, apply a hardened signature, verify the result, and optionally create a ZIP. `script/build_and_run.sh` uses the same staging path, so local runs do not drift from release metadata. See [the Xcode migration note](docs/XCODE_MIGRATION.md).

An ad-hoc build is useful for local validation only; Gatekeeper will not accept it as a public download. A direct public release must use a **Developer ID Application** identity and Apple notarization:

```bash
make macos-release \
  VERSION=1.0.0 \
  BUILD_NUMBER=1 \
  ARCHITECTURE=universal \
  SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
  NOTARY_PROFILE=tetherpane-notary
```

Universal builds require a selected, licensed full Xcode installation. A Command Line Tools-only or unselected-Xcode environment can validate the Apple-silicon SwiftPM fallback but cannot produce the public universal archive. See [the release runbook](docs/RELEASING.md) before publishing any asset.

## Device management

The sidebar separates currently connected devices from saved offline devices, then offers the two user-facing connection choices: **USB-C · Automatic** and **Wi-Fi Only · Wireless Debugging**. A saved row is anchored only to an exact USB serial, an explicitly observed secure mDNS service, or an emulator serial. Display names and IP suffixes never merge endpoints into an invented physical-phone identity, and dynamic IP addresses are not persisted.

Direct USB disconnects when the cable is unplugged. A secure wireless device exposes **Disconnect on This Mac**, which runs exact `adb disconnect` commands, stops targeting that route locally, and retains the device as **Disconnected on this Mac**. Android may still remember and automatically advertise this Mac while Wireless Debugging is enabled; reconnecting normally does not require pairing. **Forget from List** removes only an offline local row. Revoking trust still happens in Android's Wireless Debugging settings.

USB-assisted Wi-Fi keeps its separate **Turn Off** action because ordinary disconnection would leave the unencrypted listener running. Mirror quality uses a segmented picker and device audio/recording use always-visible native toggles, so the common settings do not depend on a small disclosure target. Exact endpoint and process details remain in **Advanced Details**, opened from the sidebar Utilities section or the Session menu.

## Wi-Fi mirroring

Stock scrcpy uses ADB, so merely sharing an SSID is not sufficient. The Mac app supports two honest setup paths.

### Wireless Debugging — recommended

This path does not require an initial USB connection. Android must visibly authorize the Mac through its system Wireless Debugging UI. Pairing is normally remembered, but Android may expire or revoke inactive host keys, so re-pairing remains a supported recovery path.

1. Put the Mac and Android device on the same Wi-Fi network.
2. On Android, enable Developer options and turn on **Wireless debugging**.
3. In the Mac control center, choose **Wi-Fi Only**, then **Set Up Wireless Debugging…**, and follow the Android guidance.
4. On Android, choose **Pair device with pairing code** and keep the six-digit dialog open.
5. Enter that code in the Mac app and choose **Pair and connect over Wi-Fi**.
6. The Mac pairs through stock `adb`, connects the separate connection endpoint, and verifies the exact authorized wireless serial before presenting it as ready. If endpoint association is ambiguous, the connections remain separate rather than being assigned an invented phone identity.

Pairing codes are sent to `adb` through standard input, never placed in process arguments, logged, or persisted. The app rediscovers dynamic ports instead of saving them as device identity.

When a phone is already authorized over USB, **Open Developer Options on phone** asks Android to show the public Developer Options screen through that exact USB endpoint. Android still requires the user to turn on Wireless debugging and approve pairing manually; the Mac app never attempts a hidden settings toggle.

### Use USB once — until the phone restarts

For users who do not want to leave Wireless Debugging enabled, connect and authorize the phone over USB, choose **Wi-Fi Only**, expand **Use USB once (until restart)**, and review the USB-assisted setup. After explicit trusted-network consent, the app:

1. Reads the selected phone's current Wi-Fi IPv4 address through its authorized USB transport.
2. Runs `adb -s <exact-usb-serial> tcpip 5555`.
3. Connects `adb` to `<phone-ip>:5555`, then independently verifies that exact wireless serial in a fresh ADB discovery result.
4. Tells the user when the cable can be removed.

This classic TCP/IP mode normally ends when the phone restarts or its ADB/network state resets, so the USB bootstrap must then be repeated. Use it only on a trusted private LAN: it exposes an ADB listener on TCP port 5555 and classic ADB TCP/IP traffic is not encrypted. Guest/corporate Wi-Fi may block discovery or peer traffic.

The ready workspace keeps **Turn Off USB-assisted Wi-Fi** visible while that explicitly proven route is active. The app never persists an IP address as device identity. As soon as a consented legacy setup starts, it saves only the exact USB source serial as a conservative “possible listener” risk; after interruption or relaunch, the app keeps warning until that same USB source can run `adb -s <exact-usb-serial> usb`. A currently verified wireless route can instead run `adb -s <exact-wireless-serial> usb` and remove only that stale network transport with an exact `adb disconnect`. Simply disconnecting the Mac would not close the listener, and Android's separate Wireless Debugging setting is unchanged.

If two USB endpoints expose the same display name, the basic workspace asks the user to disconnect all but one instead of inventing labels or choosing a physical phone silently. Raw endpoint serials remain diagnostic data in Advanced.

The unreliable QR experiment was removed from the product UI. Pairing-code setup is the maintained Wireless Debugging path.

See [Stock scrcpy 4.1 over Android Wireless Debugging](docs/research/stock-scrcpy-wireless-debugging.md) for the primary-source protocol and platform constraints.

## Layout

```text
.github/                      CI and dependency-update policy
Configuration/macOS/         canonical bundle metadata, artwork, and privacy declaration
Design/AppIconConcepts/       generated app-icon directions
TetherPane.xcodeproj/         native macOS app target and shared scheme
apps/android/                 Kotlin/Compose companion and Gradle wrapper
Sources/AirDroidDomain/       typed devices and session configuration
Sources/AirDroidScrcpy/       scrcpy argument and process adapter seam
Sources/AirDroidMac/          SwiftUI control center
Sources/AirDroidMacSeamTests/ deterministic Swift seam test runner
Sources/TetherPaneUIFixtureSupport/ isolated inert fixture identifiers and presentation profile
engines/scrcpy/               pin and compatibility note
script/                       developer, package, release, and verification commands
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

Production-behavior tests cross only these public seams: `ConnectionCoordinator`, `ConnectionEndpointClassifier`, `DeviceDirectory`, `DeviceDiscovery`, `PairingClient`, `WirelessConnectionClient`, `MirroringEngine`, `ScrcpyCommandBuilder`, optional Android onboarding/settings, and the root command interface. The coordinator exposes typed workspace, route provenance, scoped feedback, and stale-operation rejection. The directory reduces exact endpoint observations into connected, authorization-required, locally disconnected, and saved-offline rows without merging ambiguous physical identities. The classifier owns exact endpoint formatting and evidence precedence. System process, binary lookup, filesystem, and Android settings adapters are the true system edges; views consume typed state, not raw command output.

Visual-QA fixture identifiers and their process-local presentation resolver live in `TetherPaneUIFixtureSupport`, not in the device/session domain. Its seam contract proves that appearance and accessibility overrides activate only for a recognized inert fixture.

The active Command Line Tools-only Swift toolchain does not expose XCTest or Swift Testing, so the Swift seam contracts are a SwiftPM executable (`AirDroidMacSeamTests`) run by `make macos-test`. This is a real failing-process contract runner, not a zero-test `swift test` result. Full-Xcode CI also builds the shared native scheme through `make xcode-project-test`. The release pipeline has a separate integration contract at the root command seam; `make macos-release-test` verifies the final bundle and archive rather than shell implementation details.
