# Tauri 2 and scrcpy stack options

Research date: 2026-07-13  
Scope: whether Tauri 2 can power both the macOS scrcpy client and Android companion, and what it changes about media, process, and platform-specific work.

## Conclusion

Tauri 2 can target both macOS and Android, but it would not turn this into one portable application. The practical Tauri architecture would be a WebView UI and Rust orchestration on Mac, plus custom Kotlin plugins/services on Android. Protocol, pairing, configuration, and device/session models could be shared in Rust; capture, permission, service, and lifecycle work would remain platform-specific.

For a fast Mac launcher/control panel around a separate stock scrcpy window, Tauri is defensible. For a deeply macOS-style product with a platform-heavy Android roadmap, SwiftUI/AppKit plus Kotlin/Compose is the lower-complexity production choice.

## What Tauri supports

- Tauri uses a Rust core with HTML/CSS/JavaScript rendered by the operating system WebView; macOS uses WebKit. A Mac-style interface is therefore recreated in web UI rather than composed from SwiftUI/AppKit controls. [process model](https://v2.tauri.app/concept/process-model/)
- Tauri 2 has Android build targets and generates an Android Studio project underneath. Common configuration can be overlaid with platform-specific configuration. [development workflow](https://v2.tauri.app/develop/), [platform configuration](https://v2.tauri.app/reference/config/#platform-specific-configuration)
- Its mobile plugin model supports native Kotlin/Java methods and Android permission requests. Kotlin may call shared Rust through JNI when it needs a direct native connection. [mobile plugins](https://v2.tauri.app/develop/plugins/develop-mobile/)
- The Mac app can bundle external binaries as sidecars and manage process input/output/events. That is a reasonable mechanism for packaging and launching a pinned scrcpy 4.1/ADB toolchain. [sidecars](https://v2.tauri.app/develop/sidecar/)
- The same process pattern does not apply to Android: Tauri's shell plugin supports process execution on desktop, while mobile support is limited to opening URLs. [shell platform support](https://v2.tauri.app/plugin/shell/#supported-platforms)

## scrcpy-specific implications

Bundling and launching stock scrcpy does not embed its SDL mirror surface into the Tauri window. Tauri's sidecar API manages a process, not a foreign native window. The first Tauri product would therefore have a settings/control window plus scrcpy's separate device window.

An integrated mirror needs a deeper architecture regardless of the surrounding UI toolkit:

- fork/refactor the scrcpy desktop client and expose its media/control lifecycle to the host application; or
- implement a matching client that consumes scrcpy's encoded video/audio and control channels.

The latter has maintenance cost because the official developer documentation describes the protocol as internal, changeable at any time, and exact-version matched. [scrcpy developer protocol](https://github.com/Genymobile/scrcpy/blob/master/doc/develop.md#protocol)

Tauri commands/events are appropriate for configuration, device state, and actions. They should not be the decoded-video path. The documentation describes JSON events as asynchronous and potentially unordered, and recommends Channels for ordered/high-throughput data; even Channels should be benchmarked before placing video frames across the WebView boundary. Keep decoding, rendering, and audio native/Rust unless a real prototype proves otherwise. [calling Rust](https://v2.tauri.app/develop/calling-rust/)

## Android implications

A Tauri Android UI would still need Kotlin-owned integrations for the important future companion capabilities:

- foreground services and notifications;
- MediaProjection and playback-audio consent;
- optional Accessibility service;
- notification access and reply actions;
- shares, storage pickers, local-network permissions, and OEM lifecycle recovery.

Tauri can organize these as mobile plugins, but it does not remove them. The shared UI surface is also limited because the Mac is a controller/workspace while the phone is primarily an onboarding, permission, status, and sharing companion.

## Options

| Option | Strength | Cost/risk | Verdict |
| --- | --- | --- | --- |
| Tauri Mac + Tauri Android | One frontend ecosystem and shared Rust | Substantial custom Kotlin remains; WebView/IPC and platform integration boundaries | Viable, but sharing is less valuable than it appears |
| Tauri Mac + native Android | Fast web-built Mac controller, straightforward Kotlin companion | Mac UI is not native SwiftUI; integrated video is still custom | Reasonable if web UI speed is the primary goal |
| SwiftUI Mac + native Android | Best platform fit and simplest ownership of OS APIs | Two UI implementations | Recommended |
| Shared native/Rust core later | Shares protocol, crypto, state/config logic without forcing UI parity | FFI/build complexity must be justified | Add only after stable contracts emerge |

## Decision

Do not choose Tauri merely to claim a single codebase. Use one monorepo, native interfaces, and shared contracts. If a short Tauri experiment is desired, gate it on a very narrow question: can it deliver the intended Mac control center and integrated low-latency mirror without routing decoded frames through the WebView or retaining an awkward unmanaged second window?
