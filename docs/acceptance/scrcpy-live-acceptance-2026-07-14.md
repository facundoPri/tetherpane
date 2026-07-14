# Stock scrcpy live acceptance — 2026-07-14

Scope: the package-first SwiftUI macOS app controlling the separately windowed, locally installed stock scrcpy 4.1 client. The live ADB serial was rediscovered immediately before use and is intentionally omitted from this note.

## Environment

- macOS 26.5.2 on Apple silicon.
- Swift 6.3.3.
- ADB 37.0.1.
- scrcpy 4.1 from Homebrew.
- Motorola edge 40 pro, Android 16 / API 36, authorized over USB.
- The same phone was later available through remembered Wireless Debugging and the USB-bootstrapped classic TCP/IP endpoint represented here by the documentation-only address `192.0.2.44:5555`.

## Passed UI sessions

### Responsive, audio, and recording

The real SwiftUI control center selected the authorized Motorola, kept **Responsive** and **Forward device audio** enabled, enabled **Record next session**, and started/stopped the session through its Mirror button.

The running child used the selected exact serial plus:

```text
--video-codec=h264
--max-size=1280
--max-fps=60
--video-bit-rate=8M
--record=<Movies/TetherPane/timestamped-file.mp4>
```

There was no `--no-audio` argument. After Stop, the Advanced inspector showed the bounded process tail including stock scrcpy 4.1, the Metal renderer, a 576x1280 texture, recording start, and recording completion. `ffprobe` verified a playable MP4 containing H.264 video and 48 kHz stereo Opus audio.

### High Quality and audio opt-out

The real SwiftUI controls selected **High Quality**, turned **Forward device audio** off, and started/stopped another session. The running child used the same exact selected serial plus:

```text
--video-codec=h265
--max-size=1920
--max-fps=60
--video-bit-rate=16M
--no-audio
```

The inspector reported a Metal texture of 864x1920 and retained the expected child exit status `2` after the app requested termination. The engine treats that status as expected after an explicit Stop; an exit from an active session remains a typed reconnectable failure.

### USB-bootstrapped Wi-Fi until restart

The live Motorola used `wlan1` rather than `wlan0`. The adapter first checked the conventional interface, then correctly recovered the phone's private address from `ip -4 route`, ran `adb -s <exact-usb-serial> tcpip 5555`, and connected the endpoint represented here as `192.0.2.44:5555`.

The refreshed SwiftUI sidebar showed three distinct rows:

- **USB**
- **Wi-Fi · until restart**
- **Wi-Fi · Wireless Debugging**

The real UI selected **Wi-Fi · until restart** and showed `Authorized via Wi-Fi until restart`. Mirror, Stop, and Reconnect were exercised through the UI. The live child process and Advanced inspector both proved the exact invocation began with:

```text
--serial=192.0.2.44:5555
--video-codec=h264
--max-size=1280
--max-fps=60
--video-bit-rate=8M
```

Audio stayed enabled because no `--no-audio` argument was present. scrcpy 4.1 reported the Android 16 Motorola, Metal renderer, and a 576x1280 texture. Stop terminated the exact process and Reconnect launched the same TCP/IP serial again.

The **Open Developer Options on phone** button also passed live UI acceptance: through the selected authorized USB transport it opened `com.android.settings/.Settings$DevelopmentSettingsActivity` on the phone and told the user that Android still requires the Wireless Debugging toggle and pairing approval manually.

For the unencrypted legacy listener, the selected device also exposes **Turn off USB-assisted Wi-Fi**. Its tested seam runs `adb -s <exact-legacy-serial> usb`, then removes the stale host endpoint with `adb disconnect <exact-legacy-serial>`. Physical acceptance confirmed port 5555 closed and `service.adb.tcp.port` became `0`; Motorola briefly retained an offline host row until the exact disconnect removed it. Android's separate secure Wireless Debugging setting remained `1`. The USB-assisted endpoint was then restored successfully for the final unplug test.

## Telemetry and diagnostics

Unified logging showed one concise sequence per live session:

```text
scrcpy start requested preset=<preset> audio=<boolean> recording=<boolean>
scrcpy session started
scrcpy stop requested
scrcpy session stopped
scrcpy child exited after stop exitStatus=2
```

No serial, recording path, device content, or raw process output is written to unified logs. Raw scrcpy output is kept only as a 40-line in-memory tail in the user-opened Advanced inspector. Discovery polling is debug-level; info telemetry emits only when the summarized discovery state changes.

## Still pending

- The cable remained physically attached during this acceptance. scrcpy demonstrably targeted the Wi-Fi endpoint represented here as `192.0.2.44:5555`, not USB, but final cable-removal acceptance still requires the user to unplug it and repeat Mirror once.
- Wireless Debugging was already enabled and already authorized, so mDNS exposed `_adb-tls-connect._tcp` but no fresh `_adb-tls-pairing._tcp` service. Fresh six-digit pairing remains a separate manual acceptance if it is still required.
