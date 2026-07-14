# scrcpy UI product and architecture recommendation

Research date: 2026-07-13  
Decision scope: a polished macOS scrcpy client, a future Android companion, Basic and Advanced modes, and a monorepo that can grow into broader Android-to-Mac continuity.

> **Status update — 2026-07-14:** The current stock-scrcpy product is intentionally SwiftUI-only at runtime; neither supported connection route depends on an Android companion. Earlier statements below about a companion-led product shape are historical future context, not a current requirement. The earlier claim that secure pairing remains until explicit revocation is also superseded: Android may expire inactive host authorization, so re-pairing is a supported recovery path. See [Stock scrcpy 4.1 over Android Wireless Debugging](stock-scrcpy-wireless-debugging.md) for the current security and lifecycle contract.

## Recommendation

Build the production applications natively in one monorepo:

- **macOS:** SwiftUI, with focused AppKit integration and a native media layer when the mirror becomes embedded.
- **Android:** Kotlin and Jetpack Compose.
- **Shared:** versioned protocol/configuration schemas, capability models, test vectors, and later an optional Rust core where sharing produces real value.
- **First mirroring engine:** a pinned, packaged **scrcpy 4.1** client/server pair, exposed through a typed `ScrcpyEngine` boundary rather than raw command strings in the UI.

Tauri 2 can build macOS and Android applications and is viable for a web-styled Mac controller that launches scrcpy as a sidecar. It does not make the platform-heavy Android work portable, and launching stock scrcpy retains its separate SDL mirror window. An integrated mirror inside the application would still require a native/custom media path or deeper scrcpy-client work. Tauri is therefore a valid rapid-prototype alternative, not the recommended production foundation.

Vercel Labs Native SDK is a genuine native toolkit and an interesting Mac experiment. As of this research date it is v0.5.1, pre-1.0, desktop-first, and explicitly experimental on mobile. It should not be the Android foundation. A time-boxed Mac video-surface experiment is reasonable, but it should not delay the SwiftUI path.

## The unavoidable scrcpy onboarding constraint

Stock scrcpy does **not** work through permissions granted to an installed Android companion. It pushes its server to the device through ADB and starts it as Android's privileged `shell` user. This is what enables high-performance screen/audio capture and broad input injection without root or a permanently installed phone app. [scrcpy overview](https://github.com/Genymobile/scrcpy), [scrcpy developer guide](https://github.com/Genymobile/scrcpy/blob/master/doc/develop.md)

For Wi-Fi use on Android 11+, the user must enable Developer Options and Wireless Debugging, then authorize the Mac using Android's pairing UI. The product can make this a clear, guided flow and can discover devices without asking for an IP address, but an ordinary Android app cannot silently enable or authorize ADB. Pairing is normally remembered, but Android may expire inactive authorization or the user may revoke it; the product therefore keeps re-pairing as an ordinary recovery path. Android 17 with ADB 37 adds automatic reconnection when the device returns to a trusted Wireless Debugging network. [Android wireless debugging](https://developer.android.com/studio/run/device#wireless)

The honest scrcpy-first promise is therefore:

> Complete one guided system setup once; after that, open the Mac app and click Mirror without a terminal or IP address.

On older Android versions, OEM builds, guest Wi-Fi, or after debugging authorization is revoked, the user may occasionally need to revisit Wireless Debugging. The UI should diagnose that state rather than claiming that the phone is simply offline.

An Android companion remains valuable for later continuity features, a public-API mirroring engine, onboarding help, notifications, files, camera, and connection status. It is not required to run scrcpy and cannot substitute for ADB authorization.

## Why native apps are the better fit

| Concern | Tauri 2 on both platforms | SwiftUI + Kotlin/Compose |
| --- | --- | --- |
| Shared UI | Possible through a WebView frontend | Deliberately separate, platform-appropriate UI |
| macOS look and behavior | Must reproduce Mac conventions in web UI | Native controls, menus, windows, accessibility, input |
| Bundle/launch scrcpy | Supported through desktop sidecars | Supported through a managed child process |
| Embed stock scrcpy window | Not supplied by the sidecar API | Not automatic either; requires a custom/forked client |
| Android services and permissions | Requires custom Kotlin Tauri plugins and lifecycle bridging | First-class Kotlin implementation |
| High-rate video path | Should remain outside JSON/WebView IPC | Native decode/render path is straightforward to own |
| Long-term platform risk | WebView, Rust, Kotlin plugin, and IPC boundaries | Two native applications plus optional shared core |

Tauri's mobile support is real, and its mobile plugin system permits Kotlin. That is exactly why it does not remove the difficult Android work: `MediaProjection`, foreground services, Accessibility, notification access, shares, and OEM lifecycle handling still live in native Android code. On mobile, Tauri's shell plugin cannot spawn arbitrary processes, so the macOS sidecar pattern does not transfer to Android. [Tauri architecture](https://v2.tauri.app/concept/architecture/), [mobile plugins](https://v2.tauri.app/develop/plugins/develop-mobile/), [sidecars](https://v2.tauri.app/develop/sidecar/), [shell platform support](https://v2.tauri.app/plugin/shell/#supported-platforms)

## Product shape

### Basic mode

The default interface should avoid exposing scrcpy terminology. It needs one primary **Mirror** action, remembered devices, visible connection health, and a small set of intent-based presets:

- **Responsive:** prioritize H.264, a sensible resolution cap, low buffering, and low input latency.
- **High Quality:** prefer H.265 where the phone reports a reliable encoder, with a higher resolution/bitrate budget.
- **Smooth Video:** allow more audio/video buffering to absorb Wi-Fi jitter.
- **Data/Battery Saver:** lower resolution, bitrate, and frame-rate ceiling.

Presets should be capability-aware rather than hardcoded promises. scrcpy supports configurable resolution, bitrate, frame-rate ceiling, H.264/H.265/AV1, multiple encoders, audio forwarding, recording, camera capture, clipboard, HID input, gamepads, and virtual displays. The application should inspect the device and select a supported configuration, while explaining any fallback. [scrcpy 4.1 features](https://github.com/Genymobile/scrcpy), [video options](https://github.com/Genymobile/scrcpy/blob/master/doc/video.md), [audio options](https://github.com/Genymobile/scrcpy/blob/master/doc/audio.md)

### Advanced mode

Advanced mode should be an inspector over the same typed session configuration, grouped by purpose:

1. **Connection:** transport, ADB state, serial, IP/port, pairing/reconnect, and diagnostic logs.
2. **Video:** source, display/camera, resolution or maximum size, FPS ceiling, bitrate, codec, encoder, crop, orientation, and buffering.
3. **Audio:** enablement, source, codec, bitrate, duplication, buffer, playback, and microphone options.
4. **Input:** control enablement, keyboard/mouse mode, clipboard synchronization, gamepad, and screen-off behavior.
5. **Recording:** output path, container, audio/video selection, and time limit.
6. **Window/device:** fullscreen, always-on-top, borderless mode, keep-awake, show touches, and screen power.
7. **Diagnostics:** negotiated codec/encoder, actual FPS, disconnect reason, scrcpy output, and ADB output.

Settings should disclose whether they apply immediately or require the mirror session to restart. In particular, stock scrcpy recording is configured when a session starts; a live start/stop recording control may require a restart or later client modification. [recording documentation](https://github.com/Genymobile/scrcpy/blob/master/doc/recording.md)

## Mirroring implementation stages

### Stage 1: useful product around upstream scrcpy

The Mac app owns discovery, pairing guidance, capability inspection, presets, settings, process lifecycle, logs, recordings, and reconnect behavior. It launches the exact pinned scrcpy 4.1 client/server combination and lets upstream scrcpy display its normal SDL mirror window.

This is the shortest path to a product that preserves scrcpy's mature performance and feature surface. It also validates the product experience before committing to a media-client fork.

### Stage 2: polished two-window experience

Treat the SwiftUI application as the control center and the scrcpy window as a managed device window. Restore placement, use friendly titles, coordinate fullscreen/always-on-top state, surface errors in the control center, and make start/stop/reconnect deterministic.

### Stage 3: integrated native mirror window

Only after Stage 1 is useful, evaluate replacing the separate SDL window. This requires either:

- refactoring/forking the scrcpy desktop client and bridging it into the Mac app; or
- implementing a matching client for scrcpy's internal video, audio, and control protocol, with native decode/render/audio.

The second option carries ongoing compatibility cost: scrcpy explicitly says its client/server protocol is internal, may change at any time, and requires exact matching versions. [scrcpy protocol warning](https://github.com/Genymobile/scrcpy/blob/master/doc/develop.md#protocol)

## Monorepo shape

```text
apps/
  macos/                 SwiftUI/AppKit client
  android/               Kotlin/Compose companion
engines/
  scrcpy/                pinned upstream adapter and compatibility metadata
packages/
  protocol/              versioned schemas and generated platform models
  presets/               product presets and validation rules
  test-vectors/          pairing, configuration, and compatibility fixtures
tools/
  packaging/             dependency, signing, update, and notice automation
docs/
  product/
  architecture/
  research/
experiments/
  native-sdk-macos/      disposable, gated evaluation only
```

Do not share UI merely because the applications occupy the same repository. The Mac is a controller/workspace; the phone is a permission, status, and sharing companion. Share contracts and behavior where the concepts truly match.

## Recommended next decisions and milestones

1. **Resolve the product name.** The former AirDroid codename conflicts with an established Android remote-access/file-transfer product from Sand Studio. The public working name is now TetherPane; complete formal trademark clearance before a commercial 1.0 release. [existing AirDroid product](https://www.airdroid.com/about-us/), [official downloads](https://www.airdroid.com/download/)
2. **Approve the onboarding contract:** the first release is scrcpy-first and requires a guided one-time Wireless Debugging setup; it does not promise zero Developer Options.
3. **Write two short decision records:** native apps in a monorepo, and an engine boundary with pinned scrcpy 4.1.
4. **Design the connection state machine and onboarding screens:** new device, discovered, needs pairing, authorized, connected, mirroring, reconnecting, unsupported, and actionable failure states.
5. **Specify Basic and Advanced configuration:** define preset intent, defaults, capability fallbacks, validation, restart requirements, and persistence per device.
6. **Run a packaging feasibility spike:** bundle or acquire scrcpy/ADB safely, audit architectures and notices, launch without shell configuration, capture logs, sign/notarize the app, and decide the initial distribution channel.
7. **Build the first vertical prototype when implementation begins:** one Mac, one Android 11+ device, Wi-Fi discovery/pairing guidance, one-click start/stop, audio, Responsive/High Quality presets, recording, reconnect, and diagnostics. Keep the upstream SDL mirror window.
8. **Evaluate the integrated renderer only after the prototype meets its latency/reliability target.** The prototype determines whether deeper scrcpy integration is worth its maintenance cost.
9. **Add the Android companion when it owns real value:** onboarding/status first if useful, then the broader public-API engine, files, notifications, clipboard assistance, and camera features.

## First-release success criteria

- A new user completes setup without entering an IP address or using a terminal.
- A previously paired phone starts mirroring from one Mac action on a normal trusted network.
- Video, device audio, keyboard/mouse control, clipboard, and recording work on the supported Android range.
- The app diagnoses Wireless Debugging, authorization, codec, Wi-Fi isolation, and encoder failures in plain language.
- Responsive mode stays close enough to upstream scrcpy's latency and resource usage that the wrapper does not degrade its central value.
- Advanced mode can reproduce supported scrcpy configurations without becoming the default experience.

## Related research

- [Android platform and open-source constraints](android-platform-open-source-constraints.md)
- [Apple continuity capability benchmark](apple-continuity-capabilities.md)
- [Vercel Native SDK fit](vercel-native-apps-fit.md)
- [Tauri and scrcpy stack options](tauri-scrcpy-stack-options.md)
