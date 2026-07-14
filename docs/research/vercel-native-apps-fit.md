# Vercel Native SDK, v0, Expo, and their fit for AirDroid

Research date: 2026-07-13  
Scope: current first-party Vercel Labs, Vercel/v0, Expo, and React Native material. This note distinguishes the products and evaluates whether any of them should underpin a macOS scrcpy client and its Android companion.

## Executive conclusion

The recent Vercel technology that matters here is **Vercel Labs Native SDK**, formerly `zero-native`. It is a real application runtime and UI toolkit, not a v0 code-generation feature and not a Vercel cloud deployment service. Its default app uses declarative `.native` markup plus a deliberately constrained TypeScript core compiled to native code, with Zig as a first-class alternative and extension language. The shipping binary contains no browser, WebView, JavaScript engine, parser, or interpreter unless the app explicitly embeds web content. [Native SDK overview](https://native-sdk.dev/), [Native SDK quick start](https://native-sdk.dev/quick-start), [official repository](https://github.com/vercel-labs/native)

As of this research date, the official repository's latest release is **v0.5.1**, released July 13, 2026. The project explicitly describes itself as pre-1.0 with moving APIs. macOS is its primary and deepest platform; Android and iOS are experimental. [v0.5.1 release](https://github.com/vercel-labs/native/releases/tag/v0.5.1), [repository status and license](https://github.com/vercel-labs/native#contributing)

For AirDroid, Native SDK is **interesting enough for a bounded macOS rendering spike, but not mature enough to select as the production architecture yet**. It has several unusually relevant macOS ingredients—Metal presentation, GPU surfaces, menus, tray, dialogs, file drops, clipboard, Keychain-backed credentials, small native binaries, and strong automation—but its published surface does not yet establish a ready-made low-latency video-frame ingestion or scrcpy integration path. That is the decisive risk, not whether it can draw a polished settings screen.

It is **not a good foundation for the Android companion today**. Its Android host is experimental, currently targets one ABI (`arm64-v8a`) and Android 11+, produces a debug-signed APK, and leaves store keys/app bundles manual. More importantly, its documented host does not supply the Android-specific foreground services, `MediaProjection`, Accessibility service, permission orchestration, and persistent discovery behavior this product needs. Embedding Native SDK inside a Kotlin/Gradle host is possible through JNI/C, but then native Kotlin still owns precisely the hard lifecycle and permission work. [Native SDK platform support](https://native-sdk.dev/platform-support), [embedding documentation](https://native-sdk.dev/embed)

The architecture recommendation therefore remains **SwiftUI/AppKit on macOS and Kotlin/Compose on Android**, in one monorepo, with shared protocol definitions and test fixtures rather than a shared UI runtime. Keep Native SDK as an evaluated alternative for the Mac shell, gated by a real 1080p/60 mirroring experiment before adopting it.

## Product taxonomy

| Product | What it actually is | Targets and delivery | Relevance to AirDroid |
| --- | --- | --- | --- |
| **Vercel Labs Native SDK** | A native application toolkit/runtime: `.native` markup plus TypeScript compiled to native code, or Zig. It owns a renderer and OS hosts; no browser or JS runtime is required. | macOS, Linux, and Windows are the mature desktop surface. iOS and Android are experimental. Its CLI builds, tests, automates, packages, and has macOS signing support; it is not a hosted Vercel deployment product. | A credible experimental Mac UI shell; Android is too immature and too generic for the required privileged platform integration. |
| **v0** | Vercel's AI development agent, officially described as generating production-ready full-stack **web** apps, with best-in-class Next.js/React/Tailwind/shadcn expertise. | Browser preview and one-click web deployment to Vercel. The v0 iOS app is a mobile client for using v0, not evidence that v0 publishes native app binaries. | Useful for website/admin-console prototypes and perhaps visual exploration, not for building, running, packaging, or testing the Mac/Android binaries. [v0 FAQ](https://v0.app/docs/faqs), [v0 and Vercel integration](https://v0.app/docs/vercel-integration) |
| **v0 for iOS** | Vercel's own mobile client, built with React Native and Expo. Vercel says it shared types/helpers with the web app but deliberately did not share UI or state management, and patched native React Native behavior where needed. | iOS App Store application. | A useful monorepo/code-sharing lesson, not a framework launch. It reinforces sharing contracts/business logic rather than forcing cross-platform UI reuse. [How Vercel built the v0 iOS app](https://vercel.com/blog/how-we-built-the-v0-ios-app) |
| **Expo Agent** | Expo's separate AI app-generation workflow, currently private beta—not a Vercel product. It promises normal, downloadable Expo projects and can choose React, SwiftUI, or Jetpack Compose. | Its announcement targets iOS, Android, and web, including APK and App Store builds; it does not advertise macOS. [Expo Agent announcement](https://expo.dev/blog/expo-agent-beta), [current private beta](https://agent.expo.dev/waitlist), [Expo Agent product page](https://expo.dev/services/agent) | Potentially helpful for throwaway mobile UI prototypes. Its private-beta status and lack of a macOS target make it unsuitable as AirDroid's architecture. |
| **Expo / React Native** | A mobile application framework and tooling ecosystem. Expo permits custom Swift/Kotlin native modules; React Native can also be added incrementally to native apps. | Expo is first-class on Android, iOS, and web. macOS is an out-of-tree React Native platform and needs platform-specific setup and code. [Expo core concepts](https://docs.expo.dev/core-concepts/), [custom native code](https://docs.expo.dev/workflow/customizing/), [additional platform support](https://docs.expo.dev/modules/additional-platform-support/) | Technically capable on Android through Kotlin modules, but most of AirDroid's Android core would still be native. It adds a second runtime/build layer without creating meaningful UI sharing with a Mac-native client. |
| **Expo Application Services (EAS)** | Cloud services for compiling, signing/submitting, and updating React Native apps. EAS Update swaps compatible JS/assets; it cannot change the native code already installed in a binary. | Android and iOS mobile build/submission/OTA workflows. Native changes require a new compatible runtime/build. [Expo services](https://docs.expo.dev/core-concepts/#services), [runtime versions and updates](https://docs.expo.dev/eas-update/runtime-versions/) | Useful only if the Android app adopts React Native/Expo. It is not a media runtime, device bridge, Mac distribution service, or substitute for app-store releases after native permission/service changes. |
| **Vercel cloud** | Web application and backend infrastructure used by v0 for URLs, previews, environment variables, domains, and integrations. | Web and server workloads deployed to Vercel infrastructure. | Good for an optional account/device registry, licensing, relay coordination, landing site, documentation, admin portal, and APIs. The local mirroring data plane should not depend on it. |

## What Native SDK changes—and what it does not

### It is no longer a WebView shell

Older `zero-native` material described a Zig host around web UI. The current `vercel-labs/native` project is materially different: its normal app is a native-rendered canvas, authored in Native markup and TypeScript or Zig. TypeScript is compiled into the release binary; Node is a development/build dependency, not an application runtime. The default scaffold has a model/message/update state loop, and custom toolkit extensions, widgets, host services, and render passes are written in Zig. [Native SDK TypeScript cores](https://native-sdk.dev/typescript), [Native SDK quick start](https://native-sdk.dev/quick-start)

WebViews remain an explicit secondary composition option for existing React/Next/Vite/Svelte/Vue content. They do not make the normal binary web-based, and their presence does not solve high-rate decoded-video presentation. [Native surfaces](https://native-sdk.dev/native-surfaces), [where packages go](https://native-sdk.dev/typescript/packages)

### It is a local toolkit, not AI generation or hosted deployment

The SDK's AI story is authoring and verification: its declarative surface is designed for coding agents, the CLI ships agent skills, and every app can expose automation snapshots, input, assertions, screenshots, and replay. That could make agent-assisted UI iteration unusually effective. It does not mean v0 automatically generates or deploys these binaries, and the documented Native SDK workflow is a local CLI plus platform packaging/signing. [Native SDK overview](https://native-sdk.dev/), [Native SDK CLI](https://native-sdk.dev/cli)

### Desktop breadth is real; mobile parity is not

Native SDK documents one codebase compiling for macOS, Linux, Windows, iOS, and Android, but explicitly labels desktop as mature and mobile as experimental. On macOS, it presents through Metal and supports native menus, context menus, tray, dialogs, OS scroll behavior, clipboard, file drops, notifications, and Keychain-backed credentials. On Android, the current host is an edge-to-edge `SurfaceView` canvas with touch, keyboard/IME, insets, rotation handling, basic audio playback, and emulator verification. It does not yet wire background audio/media-session notification integration, ships one ABI, and leaves Play distribution artifacts/signing manual. [platform support matrix](https://native-sdk.dev/platform-support), [capabilities](https://native-sdk.dev/capabilities)

## Fit for the macOS scrcpy client

### What aligns well

- **Native performance posture:** Native SDK's engine and TypeScript core compile into small native binaries without a web/JS runtime. That avoids the main concern behind choosing SwiftUI over Tauri or Electron.
- **Mac product chrome:** menus, menu-bar/tray integration, dialogs, drag-and-drop, clipboard, credentials, multiple windows, native input, HiDPI behavior, and Metal presentation match the surrounding experience a polished scrcpy client needs.
- **Custom systems code:** the extension registry supports native Zig modules and custom capabilities, and an ejected build can own custom sources/build steps. Zig can call C interfaces, so a native scrcpy/FFmpeg/ADB integration is plausible in principle rather than forbidden by the framework. [extensions](https://native-sdk.dev/extensions), [quick-start escape hatch](https://native-sdk.dev/quick-start#escape-hatch-own-the-build)
- **Automated UI evidence:** built-in accessibility snapshots, input driving, screenshot assertions, and deterministic replay could be valuable for the normal and Advanced Mode control surfaces.

### The unproven blockers

- **No documented scrcpy or decoded-video surface:** `gpu_surface` is documented as the canvas used by Native SDK's UI/custom drawing, Metal-backed on macOS. The current public documentation does not specify a stable API for importing CVPixelBuffer/IOSurface/Metal textures or presenting an externally decoded 30/60-fps video stream. [native surfaces](https://native-sdk.dev/native-surfaces)
- **Launching scrcpy is not embedding scrcpy:** the effects system can spawn a subprocess, but an ordinary `scrcpy` process opens its own SDL window. That could power an early launcher, yet it would not deliver one integrated macOS window with AirDroid controls around the mirrored device. A real product path needs either a library-level/forked scrcpy client or an explicit external-frame surface.
- **Pre-1.0 churn:** the repository warns that APIs still move. Adopting it means owning framework migration risk while also solving ADB, codecs, audio, device input, signing, and updates.
- **Distribution remains partly native/manual:** Native SDK packages and signs macOS apps, but notarization remains manual. Bundling and licensing scrcpy's transitive native dependencies still belongs to this project. [platform support and signing](https://native-sdk.dev/platform-support)

### Decision gate

Before choosing it for the Mac client, a throwaway technical spike would need to prove all of the following:

1. Feed hardware-decoded Android frames into one Native SDK window at 1080p/60 without CPU readback.
2. Keep glass-to-glass latency and pointer-to-device input latency within the same budget as a direct scrcpy client.
3. Route keyboard, mouse, rotation, fullscreen, clipboard, file drop, and audio controls without a second SDL window.
4. Bundle the scrcpy server/client pieces, ADB transport, codecs, and audio dependencies into a signed and notarizable `.app`.
5. Survive sleep/wake, Wi-Fi/USB switching, disconnect/reconnect, multiple displays, and display-scale changes.
6. Pin a Native SDK version and estimate migration cost from one minor release to the next.

Until this gate passes, SwiftUI/AppKit remains the lower-risk production choice. Native SDK is best treated as a serious experiment, not an assumed shortcut.

## Fit for the Android companion

Native SDK cannot currently turn AirDroid's Android work into a shared cross-platform UI project in a useful sense. The required product is mostly Android platform integration:

- runtime permission and settings flows;
- a long-lived foreground service and notification;
- local-network discovery and pairing;
- `MediaProjection` and playback-audio capture;
- an optional Accessibility service for public-API control;
- ADB/wireless-debugging onboarding if the product exposes full scrcpy capabilities;
- Android lifecycle, OEM process-death recovery, Play policy disclosures, signing, and App Bundle release work.

The generated Native SDK Android host does not document these facilities. Its current whole-app tier generates a `NativeActivity`-style canvas host, while the embedding tier demonstrates a Kotlin/Gradle application talking to Native SDK through JNI/C. Embedding could render a Native SDK surface inside an app whose Kotlin code owns the platform lifecycle, but it would preserve all the difficult Kotlin work and add Zig/JNI/runtime integration. [Android host and caveats](https://native-sdk.dev/platform-support#the-android-host-tier), [mobile embedding contract](https://native-sdk.dev/embed#mobile-host-contract)

Expo/React Native has a more mature Android host and explicitly supports custom Kotlin modules. It is technically viable, but the conclusion is similar: the permission, capture, service, accessibility, networking, and codec layers would still be native Kotlin, while the React Native layer would mostly render onboarding/settings. With a native Mac app on the other side, there is little UI to share. [Expo custom native code](https://docs.expo.dev/workflow/customizing/)

For this product, Kotlin/Compose is the simplest place to own Android truth. A monorepo can still share wire schemas, protocol documentation, preset definitions, test vectors, generated assets, and end-to-end fixtures.

## Where these products can still help

### Native SDK

- A bounded proof of concept for the macOS shell and integrated Metal mirror surface.
- Agent-assisted exploration of the device window, connection dashboard, Quick presets, and Advanced Mode controls, backed by its automation system.
- A possible future cross-platform desktop client if Windows/Linux become product targets and the video-surface spike succeeds.

### v0 and Vercel

- AirDroid's public website, download/support pages, interactive documentation, account/device management portal, and internal admin UI.
- Optional cloud APIs for accounts, licensing, device metadata, release/update manifests, relay coordination, and telemetry ingestion.
- Preview deployments for web surfaces and documentation. None of those should sit in the same-LAN mirroring media path. [v0/Vercel integration](https://v0.app/docs/vercel-integration), [v0 deployments](https://v0.app/docs/deployments)

### Expo Agent and EAS

- Expo Agent could generate a disposable Android onboarding/settings prototype or explore a future iOS companion, but it is private beta and should not determine the architecture.
- EAS Build/Submit/Update becomes relevant only if the project deliberately chooses React Native/Expo. OTA updates cannot add or change the native capture/service/accessibility layer; those changes require a new binary. [Expo Agent](https://expo.dev/services/agent), [Expo runtime versions](https://docs.expo.dev/eas-update/runtime-versions/)

## Recommendation

Use one monorepo, but do not force one UI framework:

```text
apps/
  macos/          SwiftUI/AppKit production client
  android/        Kotlin/Compose companion
packages/
  protocol/       schemas, message IDs, compatibility fixtures
  presets/        Quick and Advanced Mode configuration definitions
  design/         shared tokens and source assets, translated per platform
  test-vectors/   pairing, discovery, control, media-session fixtures
docs/
  product/
  architecture/
  research/
experiments/
  native-sdk-macos/   disposable evaluation only
```

Run the Native SDK Mac experiment before the production scaffold is locked. If it proves direct external-video presentation and a clean scrcpy integration, reconsider it for `apps/macos`. If it only launches a separate scrcpy window or requires maintaining substantial renderer/framework patches, retain SwiftUI/AppKit. Do not use its experimental Android host for the companion at this stage.
