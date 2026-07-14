# Stock scrcpy 4.1 over Android Wireless Debugging

Research date: 2026-07-14
Scope: a SwiftUI-only macOS product orchestrating stock scrcpy 4.1 and ADB, with Android 11+ secure Wireless Debugging and classic USB-bootstrapped `adb tcpip 5555` as distinct connection modes. Android 16 is the immediate target. Sources are limited to Genymobile, Android Developers, and AOSP.

## Bottom line

Stock scrcpy has no independent Wi-Fi discovery, trust, or pairing protocol. It uses ADB for all host-to-device communication, then pushes and runs its server as Android's `shell` user. A SwiftUI Mac app can provide both wireless routes without installing an Android companion:

- **Secure Wireless Debugging (recommended):** no cable is required, but the user must enable Developer Options and Wireless Debugging in Android Settings, approve the current Wi-Fi network, and pair this Mac. The current AirDroid product implements Android's **Pair device with pairing code** path; QR is protocol background and is not implemented in the current UI. Pairing is normally remembered, but Android may expire or revoke an inactive host key.
- **USB-assisted Wi-Fi (compatibility mode):** after the phone has authorized this Mac for USB debugging, the Mac app can run the documented `adb tcpip 5555` workflow, connect to the phone's Wi-Fi address, and then let the user remove the cable. This legacy channel is unencrypted and normally must be enabled again after a phone reboot.

Neither route needs an installed Android app. scrcpy pushes its server over the selected ADB transport for each session and executes it as `shell`. [scrcpy 4.1 connection guide](https://github.com/Genymobile/scrcpy/blob/v4.1/doc/connection.md#tcpip-wireless), [scrcpy 4.1 developer guide](https://github.com/Genymobile/scrcpy/blob/v4.1/doc/develop.md#server), [Android ADB guide](https://developer.android.com/tools/adb#connect-to-a-device-over-wi-fi), [AOSP ADB Wi-Fi architecture](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/adb_wifi.md)

The reported symptom—scanning the former Mac QR code caused Android to try to join a network—is consistent with scanning an ADB QR through a generic camera or Wi-Fi QR reader. ADB's QR format deliberately starts with `WIFI:`, but it works only through **Settings > Developer options > Wireless debugging > Pair device with QR code**. That system scanner recognizes `T:ADB` and asks the privileged ADB service to start a pairing server; a regular camera or third-party app cannot perform that step. AirDroid has removed the unproven QR UI and now uses the system pairing-code flow. [Android pairing instructions](https://developer.android.com/studio/run/device.html#wireless), [AOSP QR contract](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/adb_wifi.md#android-studio), [AOSP Settings QR scanner](https://android.googlesource.com/platform/packages/apps/Settings/+/refs/heads/main/src/com/android/settings/development/AdbQrcodeScannerFragment.java)

## Two different wireless ADB modes

The product must not conflate these modes:

| Mode | First connection | Lifetime | Security | Relevant scrcpy behavior |
| --- | --- | --- | --- | --- |
| Legacy `adb tcpip 5555` | Requires an already-authorized ADB transport, normally USB | Survives cable removal and host disconnects during the current phone boot; normally ends on phone reboot or `adb usb`; an IP change requires a new `adb connect` | Host-key authentication remains, but AOSP describes the transport itself as unencrypted and open to eavesdropping/MITM | `scrcpy --tcpip` without an address automates the USB-first setup; `scrcpy --tcpip=host[:port]` assumes an already-listening endpoint. |
| Android 11+ Wireless Debugging | No USB; requires Android system UI pairing | Pairing is normally remembered but may expire or be revoked; the live TLS endpoint is dynamic and must be rediscovered when Wireless Debugging/network state changes | TLS-encrypted ADB with a paired host key | Pair and connect with ADB first, then launch scrcpy against the exact wireless ADB serial. |

The scrcpy 4.1 `--tcpip` option does **not** implement Android 11+ QR or pairing-code onboarding. The no-argument form uses a currently attached device to enable TCP/IP mode; the addressed form connects to an endpoint that is already listening. The secure no-cable path belongs in AirDroid's ADB layer, before scrcpy starts. [scrcpy 4.1 connection guide](https://github.com/Genymobile/scrcpy/blob/v4.1/doc/connection.md#tcpip-wireless), [AOSP comparison of legacy TCP and ADB Wi-Fi](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/adb_wifi.md#the-two-problems-adb-wifi-solves)

## Classic USB-assisted `adb tcpip 5555`

### Exact manual flow

USB debugging must already be enabled, the phone must have accepted this Mac's RSA debugging key, and `adb devices -l` must show the USB serial in `device` state. When more than one transport exists, every device command must specify the exact USB serial.

```sh
# 1. Verify and select the authorized USB transport.
adb devices -l

# 2. Read the current Wi-Fi address before restarting adbd.
adb -s <USB_SERIAL> shell ip route

# Parse the address after "src" on the active Wi-Fi route as <DEVICE_IP>.

# 3. Restart adbd with the legacy TCP listener.
adb -s <USB_SERIAL> tcpip 5555

# 4. Connect explicitly and verify the exact wireless serial.
adb connect <DEVICE_IP>:5555
adb devices -l

# 5. The cable may now be removed. Launch only the verified wireless target.
scrcpy --serial=<DEVICE_IP>:5555
```

This is the manual sequence documented by Android and scrcpy. `scrcpy --tcpip` can automate it when a suitable USB device is selected; `scrcpy --tcpip=<DEVICE_IP>:5555` connects when the listener already exists. The maintainable Mac implementation should still keep address discovery, `adb tcpip`, exact `adb connect`, device verification, and scrcpy launch as observable states rather than treating one child-process exit as the whole result. [Android USB-assisted ADB flow](https://developer.android.com/tools/adb#wireless-android10-command-line), [scrcpy 4.1 manual and automatic TCP/IP flows](https://github.com/Genymobile/scrcpy/blob/v4.1/doc/connection.md#tcpip-wireless), [ADB command reference](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/user/adb.1.md)

### What survives

| Event | Result |
| --- | --- |
| USB cable removed | The TCP listener and an established wireless ADB/scrcpy session continue. USB is only the bootstrap transport. |
| Mac app exits, `adb disconnect`, or host ADB server restarts | The phone normally keeps listening. Re-run `adb connect <current-ip>:5555`. `adb disconnect` closes the host connection; it does not switch adbd back to USB. |
| Wi-Fi drops and returns with the same IP during the same phone boot | Re-run `adb connect`; the runtime TCP-listener setting is independent of the cable and host connection. |
| Phone moves networks or receives a new IP | The old serial/address is stale. Rediscover `_adb._tcp` or obtain the new address, then connect to `<new-ip>:5555`. Never persist the IP as device identity. |
| `adb -s <DEVICE_IP>:5555 usb` | adbd restarts in USB mode and closes the legacy TCP listener. With no cable attached, the device then disappears from ADB until USB is connected again or another wireless mode is enabled. |
| Phone reboot | On standard production Android, the listener normally disappears and USB bootstrap must be repeated. |

The reboot behavior follows directly from AOSP: `adb tcpip` writes the runtime property `service.adb.tcp.port`, while Android reserves the `persist.` prefix for values that survive reboot. adbd can also read an OEM/root-set `persist.adb.tcp.port`, so modified/vendor builds may behave differently; the product contract should be the standard non-persistent case. [AOSP `restart_tcp_service`](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/daemon/restart_service.cpp), [AOSP adbd listener selection](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/daemon/main.cpp), [AOSP persistent-property convention](https://source.android.com/docs/core/architecture/configuration/add-system-properties#property-name)

To stop safely, distinguish these actions:

```sh
# Close this Mac's connection only; the phone still listens on port 5555.
adb disconnect <DEVICE_IP>:5555

# Close the legacy listener by switching adbd back to USB mode.
adb -s <DEVICE_IP>:5555 usb
```

AOSP explicitly describes legacy TCP ADB as unencrypted: traffic can be eavesdropped and is open to MITM attacks. Production devices still challenge hosts against authorized ADB keys, so this is not the same as an intentionally unauthenticated shell, but the transport—including scrcpy setup, video/audio/control traffic carried through ADB—is exposed to the local network. Label this mode **USB-assisted Wi-Fi — unencrypted** and do not enable it silently. AirDroid's shutdown action runs `adb usb`; a mere Disconnect button is not enough because it leaves the listener open. It then disconnects the exact host endpoint to remove the stale offline transport. `adb usb` closes only the legacy listener; if secure Wireless Debugging is also enabled, its separate TLS listener remains under Android Settings control. [AOSP legacy transport threat](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/adb_wifi.md#architecture-of-adb-wifi), [ADB `usb`, `tcpip`, and `disconnect`](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/user/adb.1.md)

## Correct Android 11+ lifecycle

### Phone prerequisites

1. The phone and Mac are on the same Wi-Fi network.
2. Developer Options is enabled.
3. Wireless Debugging is enabled and the user allows the current network. Selecting the persistent/trusted-network option reduces later setup friction.
4. The Wi-Fi must permit peer traffic and mDNS. Guest or enterprise access-point isolation and firewall rules can block discovery or the TCP connection even when both devices show the same SSID. [Android wireless ADB guide](https://developer.android.com/tools/adb#connect-to-a-device-over-wi-fi-android-11+), [Android ADB network troubleshooting](https://developer.android.com/tools/adb#wireless-android11-command-line)

Pairing is normally remembered, but it is not an eternal product guarantee. Android lets the user forget a workstation or revoke ADB authorizations, and Android 16's AOSP implementation defaults inactive host-key authorization to seven days. The cable is unnecessary for secure pairing and later use. Connection is still a live state: Wireless Debugging must be enabled for an allowed/trusted network and its currently advertised endpoint must be rediscovered rather than assumed. Wi-Fi disconnects or BSSID changes can stop the secure listener; reboot restoration is conditional; and the IP plus randomly selected TLS port may change. Android 17 and ADB 37 add Wi-Fi 2.0 reconnection improvements, so the Android 16 product must retain mDNS rediscovery, explicit `adb connect` fallback, and re-pair recovery instead of promising Android 17 behavior. [Android device setup](https://developer.android.com/studio/run/device.html#wireless), [Android ADB guide](https://developer.android.com/tools/adb#connect-to-a-device-over-wi-fi-android-11+), [Android 16 ADB authorization window](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android16-release/services/core/java/com/android/server/adb/AdbDebuggingManager.java), [Android 16 default timeout setting](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android16-release/core/java/android/provider/Settings.java), [AOSP TLS server lifecycle](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/adb_wifi.md#encrypted-traffic)

### mDNS service lifecycle

AOSP defines three service types:

| Service | Meaning | Lifetime |
| --- | --- | --- |
| `_adb._tcp` | Legacy `adb tcpip` endpoint | While legacy TCP mode is active. |
| `_adb-tls-connect._tcp` | Secure Wireless Debugging connection endpoint | While Wireless Debugging's TLS server is active. The port is selected dynamically. |
| `_adb-tls-pairing._tcp` | Temporary secure pairing endpoint | Only while a pairing server is active, either from the pairing-code dialog or after the system QR scanner accepts a valid ADB QR. |

`adb mdns services` lists the active instances that the host has discovered, including their resolved IPv4 address and port. The device publishes the services; the host ADB server consumes them. When the host sees `_adb-tls-connect`, it can auto-connect only if it already knows the device GUID from pairing. A visible connect service is therefore a **nearby endpoint**, not proof that this Mac is authorized. [AOSP mDNS architecture and service list](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/adb_wifi.md#network-advertising-mdns), [ADB command reference](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/user/adb.1.md#networking)

The secure connection service may already have been advertised before pairing begins. AOSP explicitly notes that a host cannot wait for a new `_adb-tls-connect` create event after pairing; the pairing client makes an immediate connection attempt for this reason. AirDroid should likewise issue an explicit exact-endpoint `adb connect` after a successful pair, then verify the wireless device in `adb devices -l`. [AOSP auto-connect lifecycle](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/adb_wifi.md#auto-connect)

### Pairing with a code

This is the simplest deterministic acceptance path:

1. On the phone, choose **Pair device with pairing code**. Android starts a temporary pairing server and shows a six-digit code plus a pairing address and port.
2. On the Mac, run `adb pair <pairing-host>:<pairing-port>` and supply the code when prompted.
3. Connect to the separate `_adb-tls-connect._tcp` endpoint with `adb connect <connect-host>:<connect-port>`.
4. Verify that the exact wireless transport is present in `adb devices -l`.
5. Launch `scrcpy --serial=<exact-wireless-adb-serial>`.

The pairing port and connection port are different roles and are commonly different values. Do not use the pairing endpoint as the scrcpy target. The ADB CLI formally supports `adb pair HOST[:PORT] [PAIRING_CODE]`, `adb connect HOST[:PORT]`, `adb mdns services`, and `adb devices -l`. For application code, prefer feeding the one-time secret through standard input so it is not exposed in logs or the process argument list. [AOSP command-line pairing example](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/adb_wifi.md#pair), [ADB man page](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/user/adb.1.md#networking), [ADB CLI source](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/client/commandline.cpp)

### Pairing with QR (protocol background; not implemented)

The QR payload contract is:

```text
WIFI:T:ADB;S:studio-<random-session-suffix>;P:<one-time-secret>;;
```

The `WIFI:` prefix is an envelope borrowed from the Wi-Fi QR grammar; it does not mean "join this SSID." `T:ADB` selects the ADB handler. `S:` requests the exact `_adb-tls-pairing._tcp` instance name that the phone must publish, and `P:` carries the shared pairing secret. AOSP describes the QR service name as `studio-` plus a randomized suffix and the QR secret as a one-time pairing secret. [AOSP QR contract](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/adb_wifi.md#pair-with-qr-code)

The complete QR transaction is:

1. The Mac creates a random `studio-...` service name and secret in memory and displays their ADB QR payload.
2. The user opens Android's **Wireless Debugging** page and chooses **Pair device with QR code**.
3. The **system Settings scanner** parses the payload and invokes `IAdbManager.enablePairingByQrCode(serviceName, secret)`.
4. Android starts a temporary pairing server that advertises that exact service name under `_adb-tls-pairing._tcp`.
5. The Mac polls/browses mDNS for that exact session service, then runs `adb pair <resolved-pairing-endpoint>` with the same in-memory secret.
6. On success, the Mac connects to the selected phone's `_adb-tls-connect._tcp` endpoint, verifies the exact wireless ADB serial, and launches scrcpy with that serial.

The system Settings implementation obtains `IAdbManager` from the system service and calls `enablePairingByQrCode`; the ADB service enforces `android.permission.MANAGE_DEBUGGING`. That permission is `signature|privileged` and explicitly not for third-party apps. The AOSP QR scanner activity is an internal Settings component, not a supported exported activity contract for companion apps. [AOSP Settings scanner](https://android.googlesource.com/platform/packages/apps/Settings/+/refs/heads/main/src/com/android/settings/development/AdbQrcodeScannerFragment.java), [AOSP ADB permission enforcement](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/adb/AdbService.java), [AOSP permission declaration](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/res/AndroidManifest.xml), [AOSP Settings manifest](https://android.googlesource.com/platform/packages/apps/Settings/+/refs/heads/main/AndroidManifest.xml)

If QR onboarding is reconsidered later, its acceptance contract must include all of the following:

- Say **"Open Wireless Debugging, then tap Pair device with QR code"**, not merely "scan this QR."
- Explicitly warn against the regular Camera app, Google Lens, a Wi-Fi QR scanner, or another third-party scanner. Those paths do not invoke the privileged ADB pairing service and may interpret the `WIFI:` envelope as network configuration.
- Keep the QR session alive while polling for the exact `studio-...` pairing service; expire it cleanly and never log the payload or secret.
- Distinguish "QR scanned" (pairing service appeared), "ADB paired," "ADB connected," and "scrcpy started." A rendered QR is not acceptance evidence.

The current repository intentionally contains no QR payload/session implementation. Its secure onboarding is pairing-code based: the [pairing seam](../../Sources/AirDroidDomain/PairingClient.swift) accepts an mDNS-discovered pairing candidate and a short-lived code, the [ADB implementation](../../Sources/AirDroidScrcpy/ADBPairingClient.swift) supplies the code through standard input, and the [SwiftUI flow](../../Sources/AirDroidMac/Views/WirelessCandidateDetailView.swift) guides the user to Android's pairing-code dialog. QR should not return until its system-scanner contract and full pairing lifecycle are proven on a physical phone.

## What the authorized Mac can open or toggle

### Opening Developer Options is supported

With an authorized USB ADB connection, the Mac app can bring Android's public Developer Options screen to the foreground:

```sh
adb -s <USB_SERIAL> shell am start \
  -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS
```

`Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS` is a public, required platform action for the development-settings screen. AOSP Settings exports the matching activity. This gives the product a legitimate **Open Developer Options on phone** button while USB ADB is available. It does not give the host ownership of the phone UI, and the user may still need to unlock the device, enter **Wireless debugging**, approve the current network, and select a pairing method. Android exposes no documented public action dedicated to the nested Wireless Debugging fragment; directly naming AOSP Settings internals would be OEM-fragile. [Android Settings action](https://developer.android.com/reference/android/provider/Settings#ACTION_APPLICATION_DEVELOPMENT_SETTINGS), [AOSP Settings manifest](https://android.googlesource.com/platform/packages/apps/Settings/+/refs/heads/main/AndroidManifest.xml)

### Silently enabling secure Wireless Debugging is not a supported product API

AOSP reveals why tempting shell workarounds are not a sound contract:

- the Settings UI writes the hidden global key `adb_wifi_enabled`;
- `AdbService` observes that key and starts/stops the TLS transport;
- ADB shell has development permissions that can write secure settings on AOSP; but
- `adb shell cmd adb` exposes only support queries (`is-wifi-supported` and `is-wifi-qr-supported`), not an enable operation.

Therefore, an already-authorized shell may technically make `settings put global adb_wifi_enabled 1` change state on a particular AOSP/OEM build. AirDroid should **not** ship that as its secure onboarding: `ADB_WIFI_ENABLED` is `@hide`, the command is undocumented, OEM behavior can differ, and it bypasses the Settings UI that checks Wi-Fi state and presents the network-approval warning. Direct pairing APIs such as `enablePairingByQrCode` are protected by `MANAGE_DEBUGGING`, a signature/privileged permission. [AOSP hidden setting](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/provider/Settings.java), [AOSP Wireless Debugging switch](https://android.googlesource.com/platform/packages/apps/Settings/+/refs/heads/main/src/com/android/settings/development/WirelessDebuggingEnabler.java), [AOSP `AdbService`](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/adb/AdbService.java), [AOSP shell permissions](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android16-release/packages/Shell/AndroidManifest.xml), [AOSP supported ADB shell commands](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/adb/AdbShellCommand.java), [AOSP `MANAGE_DEBUGGING`](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/res/AndroidManifest.xml)

If the product needs a one-click transition after USB authorization, the documented action is `adb tcpip 5555`. That enables the separate legacy unencrypted listener; it does **not** legitimately toggle Android 11+ secure Wireless Debugging.

## No Android companion is required

Both stock-scrcpy routes are complete with only the SwiftUI Mac app and Android's built-in system components:

- **Secure mode:** Android Settings owns enablement, network approval, QR/code UI, and paired-host trust. Host `adb` owns pairing, mDNS consumption, connection, and its private key.
- **USB-assisted mode:** the already-authorized host tells the device's built-in adbd to restart on TCP port 5555.
- **Mirroring:** scrcpy pushes its server JAR to `/data/local/tmp` and executes it as `shell` for the session; it is not a conventionally installed companion APK.

An Android companion could provide friendly app-level discovery or a separate `MediaProjection` engine, but neither helps stock scrcpy obtain ADB authority. It is deliberately outside the revised SwiftUI-only product. [scrcpy 4.1 server execution](https://github.com/Genymobile/scrcpy/blob/v4.1/doc/develop.md#execution), [AOSP ADB Wi-Fi components](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/adb_wifi.md)

## Implications for the Mac device sidebar

The SwiftUI app should merge USB and ADB's two network service types without pretending discovery proves authority:

| Sidebar state | Evidence | Allowed action |
| --- | --- | --- |
| USB authorization required | USB transport is `unauthorized` | Ask the user to unlock the phone and accept Android's RSA dialog. |
| USB connected | Exact USB transport is `device` | Mirror over USB, open Developer Options, or offer the warned USB-assisted Wi-Fi action. |
| Secure Wireless nearby | `_adb-tls-connect._tcp` is visible | Try exact `adb connect` for a previously paired identity; otherwise offer system pairing guidance. |
| Secure pairing window active | `_adb-tls-pairing._tcp` is visible | Pair only with the user-entered code or the exact active QR session secret. |
| Legacy TCP listener nearby | `_adb._tcp` is visible, normally on port 5555 | Label **Unencrypted**; connect only by explicit user choice or as the result of this app's current USB-assisted flow. |
| Authorized wireless device | Exact TCP transport appears as `device` in `adb devices -l` | Launch scrcpy with that exact wireless serial. |
| Mirroring | scrcpy child process is healthy for that exact serial | Stop/reconnect/diagnose; for legacy mode, **Turn off USB-assisted Wi-Fi** runs `adb usb` to close only the legacy listener. |

Before pairing, `_adb-tls-connect` gives AirDroid an endpoint candidate, but not trustworthy friendly metadata on Android 16 and not authorization. Label it **Nearby over Wi-Fi — pairing required**, not "connected" or "ready to mirror." Do not persist random ports or IP addresses as device identity; rediscover the active service and associate long-term state with the paired ADB identity. Without a companion, friendly naming may remain limited until an authorized ADB connection yields `adb devices -l` metadata. Stock ADB cannot discover a same-LAN phone whose ADB listener is off; discovering every phone on Wi-Fi would require a separate companion protocol, outside this SwiftUI-only scrcpy scope. [AOSP service instance and auto-connect behavior](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/adb_wifi.md#mdns-service-instance-names), [ADB device listing](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/user/adb.1.md#devices)

Do not scan arbitrary LAN ports for phones. Secure Wireless Debugging uses a dynamically selected TLS port, and legacy mode already advertises `_adb._tcp`; mDNS is the intended discovery mechanism for both. If no expected service is visible, the actionable diagnoses are: the relevant listener is off, the network was not approved for secure Wireless Debugging, mDNS is disabled/blocked, peer traffic is isolated, or the device is no longer on the same network. [AOSP network advertising](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/adb_wifi.md#network-advertising-mdns), [Android mDNS troubleshooting](https://developer.android.com/tools/adb#wireless-android11-command-line)

## Recommended product wording

Use two explicitly different actions:

> **Secure Wireless — recommended**
>
> No cable or Android app required. On your phone, open Developer Options → Wireless debugging, approve this Wi-Fi network, choose **Pair device with pairing code**, then enter that six-digit code on the Mac. Keep the Android pairing dialog open until AirDroid reports success. Pair again if Android expires or revokes this Mac's authorization.

> **Use USB to switch to Wi-Fi — less secure**
>
> Connect and authorize the phone over USB once. AirDroid will enable legacy wireless ADB, verify the Wi-Fi connection, and then tell you when the cable can be removed. This connection is unencrypted, normally needs to be enabled again after the phone restarts, and remains listening until you turn it off.

Use **Disconnect Mac** for `adb disconnect` and the separate implemented **Turn off USB-assisted Wi-Fi** for `adb usb`. Never imply that Disconnect closes the phone's legacy port, or that `adb usb` changes the separate secure Wireless Debugging toggle. If the Mac can still see an authorized USB transport, offer **Open Developer Options on phone**; do not label it **Enable Wireless Debugging**, because the user must complete that secure setting.

## Recommended implementation and acceptance order

1. Keep the stock scrcpy engine behind an exact ADB device-serial seam.
2. Make pairing-code onboarding the deterministic baseline for secure Wireless Debugging; it removes QR-scanner ambiguity while proving no-cable TLS ADB.
3. Keep QR out of the current product. If it is revisited, require the AOSP payload contract and four observable transitions: pairing service appeared, paired, exact TLS connection authorized, scrcpy started.
4. Browse `_adb-tls-connect`, `_adb-tls-pairing`, and `_adb` continuously; treat all discovered endpoints as candidates until `adb devices -l` proves authorization.
5. Add USB-assisted legacy mode as an explicit security tradeoff. Capture the Wi-Fi address before `adb tcpip`, verify `<ip>:5555`, then tell the user the cable may be removed.
6. Do not use hidden `adb_wifi_enabled` writes or internal Settings fragments. Opening the public Developer Options activity is the limit of supported secure-setting automation.
7. Remove the Android companion from the stock-scrcpy build/run contract. No app installation or Android permission can substitute for ADB's system trust flow.
8. Test both routes independently on a physical phone: secure pairing with USB absent; legacy bootstrap over USB followed by cable removal; exact scrcpy target in both cases; reboot and IP-change recovery; `adb usb` closing the legacy listener.

The cable may be unplugged before Android 11+ secure pairing because it is not part of that workflow. In legacy mode, unplug it only after `<ip>:5555` is verified. When USB and Wi-Fi transports coexist, scrcpy requires explicit selection; never launch against “the first device.” [Android no-USB wireless debugging](https://developer.android.com/tools/adb#connect-to-a-device-over-wi-fi-android-11+), [scrcpy 4.1 device selection](https://github.com/Genymobile/scrcpy/blob/v4.1/doc/connection.md#selection)

## Safe diagnostics

The following checks reveal lifecycle state without recording pairing secrets or raw device identifiers in product logs:

```sh
adb version
adb mdns check
adb mdns services
adb devices -l
adb -s <AUTHORIZED_SERIAL> shell getprop service.adb.tcp.port
```

For a failure report, retain only tool versions, transport type, whether each expected service type was present, whether legacy port state was empty/5555, command exit status, and redacted error categories. Do not persist QR payloads, pairing codes, host keys, raw service instance names, IP addresses, or device serials in routine telemetry. Newer ADB documentation also exposes `adb server-status` and structured mDNS tracking for ADB 37/Wi-Fi 2.0, but Android 16 support must continue to work through the baseline `mdns services` and exact `pair`/`connect` commands. [ADB man page](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/user/adb.1.md), [Android ADB troubleshooting](https://developer.android.com/tools/adb#wireless-android11-command-line)
