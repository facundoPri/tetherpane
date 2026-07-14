# Stock scrcpy 4.1 over Android Wireless Debugging

Research date: 2026-07-13  
Scope: stock scrcpy 4.1 on macOS, Android 11+ secure Wireless Debugging (with Android 16 as the immediate target), QR and pairing-code onboarding, mDNS discovery, and the limits of a normal Android companion. Sources are limited to Genymobile, Android Developers, and AOSP.

## Bottom line

Stock scrcpy has no independent Wi-Fi discovery, trust, or pairing protocol. It uses ADB for all host-to-device communication, then pushes and runs its server as Android's `shell` user. Therefore, stock scrcpy can mirror without a cable, but **same Wi-Fi is not the only first-time requirement**: on Android 16 the user must enable Developer Options and Wireless Debugging, approve the Wi-Fi network, and pair this Mac's ADB host once. No prior USB connection is required for the Android 11+ secure Wireless Debugging route. [scrcpy 4.1 connection guide](https://github.com/Genymobile/scrcpy/blob/v4.1/doc/connection.md#tcpip-wireless), [scrcpy 4.1 developer guide](https://github.com/Genymobile/scrcpy/blob/v4.1/doc/develop.md#privileges), [Android wireless ADB guide](https://developer.android.com/tools/adb#connect-to-a-device-over-wi-fi-android-11+), [AOSP ADB Wi-Fi architecture](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/adb_wifi.md)

The reported symptom—scanning the Mac QR code causes Android to try to join a network—strongly indicates that the QR was scanned with a generic camera or Wi-Fi QR reader. ADB's QR format deliberately starts with `WIFI:`, but it must be scanned from **Settings > Developer options > Wireless debugging > Pair device with QR code**. That system scanner recognizes `T:ADB` and asks the privileged ADB service to start a pairing server. A generic camera or the AirDroid companion cannot perform that privileged step. [Android pairing instructions](https://developer.android.com/studio/run/device.html#wireless), [AOSP QR contract](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/adb_wifi.md#android-studio), [AOSP Settings QR scanner](https://android.googlesource.com/platform/packages/apps/Settings/+/refs/heads/main/src/com/android/settings/development/AdbQrcodeScannerFragment.java)

## Two different wireless ADB modes

The product must not conflate these modes:

| Mode | First connection | Security | Relevant scrcpy behavior |
| --- | --- | --- | --- |
| Legacy `adb tcpip 5555` | Normally requires USB to run `adb tcpip 5555` | AOSP describes the transport as unencrypted | `scrcpy --tcpip` without an address automates the USB-first setup; `scrcpy --tcpip=host[:port]` assumes an already-listening endpoint. |
| Android 11+ Wireless Debugging | No USB; requires system UI pairing | TLS-encrypted ADB with a paired host key | Pair and connect with ADB first, then launch scrcpy against the exact wireless ADB serial. |

The scrcpy 4.1 `--tcpip` option does **not** implement Android 11+ QR or pairing-code onboarding. The no-argument form uses a currently attached device to enable TCP/IP mode; the addressed form connects to an endpoint that is already listening. The secure no-cable path belongs in AirDroid's ADB layer, before scrcpy starts. [scrcpy 4.1 connection guide](https://github.com/Genymobile/scrcpy/blob/v4.1/doc/connection.md#tcpip-wireless), [AOSP comparison of legacy TCP and ADB Wi-Fi](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/adb_wifi.md#the-two-problems-adb-wifi-solves)

## Correct Android 11+ lifecycle

### Phone prerequisites

1. The phone and Mac are on the same Wi-Fi network.
2. Developer Options is enabled.
3. Wireless Debugging is enabled and the user allows the current network. Selecting the persistent/trusted-network option reduces later setup friction.
4. The Wi-Fi must permit peer traffic and mDNS. Guest or enterprise access-point isolation and firewall rules can block discovery or the TCP connection even when both devices show the same SSID. [Android wireless ADB guide](https://developer.android.com/tools/adb#connect-to-a-device-over-wi-fi-android-11+), [Android ADB network troubleshooting](https://developer.android.com/tools/adb#wireless-android11-command-line)

Pairing is durable: Android documents that the workstation remains paired until the user forgets it or revokes ADB authorizations. Connection is still a live state: Wireless Debugging must be running and its currently advertised endpoint must be discovered rather than assumed. Android 17 and ADB 37 add Wi-Fi 2.0 improvements, so the Android 16 product should not be designed around Android 17-only service metadata or reconnection behavior. [Android device setup](https://developer.android.com/studio/run/device.html#wireless), [Android ADB guide](https://developer.android.com/tools/adb#connect-to-a-device-over-wi-fi-android-11+)

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

### Pairing with QR

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

Consequences for the AirDroid QR UI:

- Say **"Open Wireless Debugging, then tap Pair device with QR code"**, not merely "scan this QR."
- Explicitly warn against the regular Camera app, Google Lens, a Wi-Fi QR scanner, or the AirDroid companion scanner. Those paths do not invoke the privileged ADB pairing service and may interpret the `WIFI:` envelope as network configuration.
- Keep the QR session alive while polling for the exact `studio-...` pairing service; expire it cleanly and never log the payload or secret.
- Distinguish "QR scanned" (pairing service appeared), "ADB paired," "ADB connected," and "scrcpy started." A rendered QR is not acceptance evidence.

The current repository's [QR payload type](../../Sources/AirDroidDomain/WirelessQRCodePairingSession.swift) and [session factory](../../Sources/AirDroidMac/Services/WirelessQRCodePairingSessionFactory.swift) are structurally aligned with the AOSP envelope. The likely product failure is not that the QR encodes a real Wi-Fi network; it is that the scanner contract and pairing lifecycle were not made unmistakable or proven end to end. The [current Mac flow](../../Sources/AirDroidMac/Models/ControlCenterStore.swift) already looks for the exact session pairing service, but its acceptance must show each lifecycle transition and the final exact wireless ADB target.

## What the Android companion can and cannot do

A normal Android companion can:

- advertise a friendly AirDroid service with Android NSD/DNS-SD so the Mac can list phones running the companion, even independently of ADB's service names;
- establish its own authenticated local control channel after an AirDroid-specific QR/code exchange;
- open the public Developer Options settings page as a best-effort onboarding shortcut and explain the remaining system steps;
- report its own app/network state to the Mac; and
- implement a separate public-API screen-sharing engine with `MediaProjection`.

Android's NSD API is specifically intended for apps to advertise named services and discover/connect to peers on a local network. That makes it a good product discovery plane, but it does not grant access to ADB. [Android NSD guide](https://developer.android.com/develop/connectivity/wifi/use-nsd), [public Developer Options settings action](https://developer.android.com/reference/android/provider/Settings#ACTION_APPLICATION_DEVELOPMENT_SETTINGS)

A normal companion cannot:

- enable Wireless Debugging silently;
- approve the current network for Wireless Debugging;
- add the Mac's key to ADB's trusted host keystore;
- call the privileged QR-pairing service;
- run the scrcpy server with the `shell` privileges stock scrcpy relies on; or
- turn a companion-only LAN connection into a stock scrcpy transport.

Those operations are protected by Android's privileged ADB service and the `MANAGE_DEBUGGING` signature/privileged permission. scrcpy's server is pushed and executed through ADB as `shell`, which is why an installed app cannot simply replace the host pairing step. [AOSP ADB service](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/adb/AdbService.java), [AOSP `MANAGE_DEBUGGING` permission](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/res/AndroidManifest.xml), [scrcpy 4.1 privileges](https://github.com/Genymobile/scrcpy/blob/v4.1/doc/develop.md#privileges)

If the product requirement is literally "install both apps, share Wi-Fi, and never enable Developer Options or pair ADB," that is a **different mirroring engine**, not stock scrcpy. The Android companion would capture through `MediaProjection`, encode, and stream to the Mac; Android requires user consent before every new media-projection session, and Android 14+ tokens are single-use. Control would also need a separate, explicitly enabled accessibility design rather than scrcpy's shell-level input injection. [Android MediaProjection guide](https://developer.android.com/media/grow/media-projection#user-consent), [scrcpy input privilege model](https://github.com/Genymobile/scrcpy/blob/v4.1/doc/develop.md#input-events-injection)

## Implications for the Mac device sidebar

The Mac should merge two discovery planes without pretending they provide the same authority:

| Sidebar state | Evidence | Allowed action |
| --- | --- | --- |
| Companion nearby | AirDroid-specific NSD service | Open onboarding/status; cannot launch stock scrcpy yet. |
| Wireless Debugging nearby | `_adb-tls-connect._tcp` is visible | Try auto-connect if previously paired; otherwise offer system pairing guidance. |
| Pairing window active | `_adb-tls-pairing._tcp` is visible | Pair only with the user-entered code or the exact active QR session secret. |
| Authorized wireless device | Exact wireless transport appears in `adb devices -l` | Launch scrcpy with the exact wireless serial. |
| Mirroring | scrcpy child process is healthy for that exact serial | Stop/reconnect/diagnose. |

Before pairing, `_adb-tls-connect` gives AirDroid an endpoint candidate, but not trustworthy friendly metadata on Android 16 and not authorization. Label it **Nearby over Wi-Fi — pairing required**, not "connected" or "ready to mirror." Do not persist random ports as device identity; rediscover the active service and associate long-term state with the paired ADB identity. A companion-advertised service can provide a friendly product identity, but it must remain a separate signal until ADB proves authorization. [AOSP service instance and auto-connect behavior](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/adb_wifi.md#mdns-service-instance-names), [Android NSD service identity](https://developer.android.com/develop/connectivity/wifi/use-nsd#register-service)

Do not scan arbitrary LAN ports for phones. Secure Wireless Debugging uses a dynamically selected TLS port and mDNS is the platform's intended discovery mechanism. If no connect service is visible, the actionable diagnoses are: Wireless Debugging is off, the network was not approved, mDNS is disabled/blocked, peer traffic is isolated, or the device is no longer on the same network. [AOSP encrypted-transport lifecycle](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/adb_wifi.md#encrypted-traffic), [Android mDNS troubleshooting](https://developer.android.com/tools/adb#wireless-android11-command-line)

## Recommended implementation and acceptance order

1. Keep the stock scrcpy engine behind an exact ADB device-serial seam.
2. Make pairing-code onboarding the diagnostic baseline first; it removes QR-scanner ambiguity while proving secure no-cable ADB.
3. For QR, retain the AOSP payload contract but redesign the copy and state machine around the system Wireless Debugging scanner and the four observable transitions: pairing service, paired, connected, mirroring.
4. Have the Mac browse `_adb-tls-connect` continuously and attempt connection only for paired identities; show unpaired endpoints as candidates.
5. Add an AirDroid NSD service to the Android companion only as a friendly discovery/onboarding channel. Do not describe it as ADB authorization.
6. After `adb devices -l` shows the exact wireless transport, unplug USB and start scrcpy with the exact wireless serial. A passing acceptance run must continue mirroring after the cable is removed.
7. If the desired consumer promise remains same-Wi-Fi-only with no Developer Options, plan a separate MediaProjection engine instead of adding permissions that cannot authorize ADB.

The cable may be unplugged before Android 11+ pairing; it is not part of this secure workflow. During development it is also safe to leave USB attached, but the app must explicitly select the wireless ADB serial because scrcpy requires explicit selection when multiple transports/devices are present. [Android no-USB wireless debugging](https://developer.android.com/tools/adb#connect-to-a-device-over-wi-fi-android-11+), [scrcpy 4.1 device selection](https://github.com/Genymobile/scrcpy/blob/v4.1/doc/connection.md#selection)

## Safe diagnostics

The following checks reveal lifecycle state without recording pairing secrets or raw device identifiers in product logs:

```sh
adb version
adb mdns check
adb mdns services
adb devices -l
```

For a failure report, retain only tool versions, whether each expected service type was present, command exit status, and redacted error categories. Do not persist QR payloads, pairing codes, host keys, raw service instance names, IP addresses, or device serials in routine telemetry. Newer ADB documentation also exposes `adb server-status` and structured mDNS tracking for ADB 37/Wi-Fi 2.0, but Android 16 support must continue to work through the baseline `mdns services` and exact `pair`/`connect` commands. [ADB man page](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/user/adb.1.md), [Android ADB troubleshooting](https://developer.android.com/tools/adb#wireless-android11-command-line)

