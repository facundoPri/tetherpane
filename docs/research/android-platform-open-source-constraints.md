# Android-to-macOS bridge constraints and architecture options

Research date: 2026-07-13  
Scope: a consumer Android app plus a native macOS companion, primarily over the same Wi-Fi network. Sources are official Android/Google Play, Apple, scrcpy, and KDE project documentation.

## Executive summary

A polished Android-to-Mac bridge is feasible without requiring an IP address or terminal. Automatic discovery, secure pairing, files, camera streaming, screen viewing, notification mirroring, and many notification replies can all be built with public APIs.

The central limit is privilege, not Wi-Fi. A normal Play-distributed Android app cannot silently reproduce Apple's first-party iPhone Mirroring:

- Android requires the user to approve each new `MediaProjection` capture session.
- Reliable remote touch and navigation require a separately enabled Accessibility service; an ordinary app cannot inject arbitrary input system-wide.
- Android 10+ prevents background apps from reading the clipboard unless the app has focus or is the default input method.
- Protected surfaces and some playback audio cannot be captured.
- Full SMS/call data requires restricted permissions and Google Play review; full RCS or third-party chat history is not exposed as a general cross-app API.

scrcpy feels unusually powerful because its Android server is started through ADB as the privileged `shell` user and uses hidden platform APIs. That is an excellent benchmark or optional advanced mode, but it is incompatible with a zero-setup consumer promise. [scrcpy developer overview](https://github.com/Genymobile/scrcpy/blob/master/doc/develop.md), [scrcpy connection guide](https://github.com/Genymobile/scrcpy/blob/master/doc/connection.md)

## Capability matrix

| Capability | Normal consumer app | Important limit |
| --- | --- | --- |
| Nearby discovery and pairing | **Yes** | Use DNS-SD/mDNS on Android and Bonjour on macOS. Android 17+ and macOS 15+ have local-network privacy prompts. [Android NSD](https://developer.android.com/develop/connectivity/wifi/use-nsd), [Android local-network permission](https://developer.android.com/privacy-and-security/local-network-permission), [Apple local-network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) |
| View the Android screen | **Yes** | Every new capture session requires an Android system consent flow; the user can stop it at any time. [MediaProjection capture](https://developer.android.com/media/platform/av-capture), [Android 14 behavior](https://developer.android.com/about/versions/14/behavior-changes-14#media-projection) |
| Mouse/touch control | **Partly** | Requires an explicitly enabled Accessibility service for gestures and global actions. It is sensitive under Play policy and needs disclosure/consent. [Accessibility gestures](https://developer.android.com/reference/android/accessibilityservice/AccessibilityService#dispatchGesture(android.accessibilityservice.GestureDescription,%20android.accessibilityservice.AccessibilityService.GestureResultCallback,%20android.os.Handler)), [Play Accessibility policy](https://support.google.com/googleplay/android-developer/answer/17105854) |
| Keyboard input | **Partly** | Accessibility can set text in cooperating editable nodes; a dedicated optional IME is more reliable but adds onboarding. Arbitrary low-level key injection is not available to an ordinary app. [Accessibility set text](https://developer.android.com/reference/android/view/accessibility/AccessibilityNodeInfo#ACTION_SET_TEXT) |
| Screen audio | **Partly** | Playback capture depends on Android version, audio usage, source-app policy, and user consent. Apps can prevent their playback from being captured. [Video and playback-audio capture](https://developer.android.com/media/platform/av-capture) |
| File send/receive | **Yes** | The clean path uses Android Sharesheet, MediaStore, and Storage Access Framework. Broad filesystem access is restricted and reviewed by Google Play. [Storage Access Framework](https://developer.android.com/training/data-storage/shared/documents-files), [all-files access](https://developer.android.com/training/data-storage/manage-all-files) |
| Automatic universal clipboard | **No, not symmetrically** | On Android 10+, only the focused app or default IME can read the clipboard. Explicit “Send to Mac,” a share action, or an optional keyboard can provide a good but not invisible flow. [Android 10 clipboard restriction](https://developer.android.com/about/versions/10/privacy/changes#clipboard-data) |
| Notifications on Mac | **Yes** | The user must grant Notification Access. Work-profile and device-policy restrictions can reduce visibility. [NotificationListenerService](https://developer.android.com/reference/android/service/notification/NotificationListenerService) |
| Reply to chat notifications | **Often** | A reply works only when the source notification exposes a compatible `RemoteInput` action; this is not a full chat-history API. [RemoteInput](https://developer.android.com/reference/android/app/RemoteInput) |
| Full SMS/MMS sync | **Possible but policy-sensitive** | SMS and call-log permissions are restricted. Cross-device synchronization is a listed permitted-use exception, but it requires a Play declaration/review and strict data handling. [Google Play SMS and Call Log policy](https://support.google.com/googleplay/android-developer/answer/10208820) |
| Full RCS/WhatsApp/Signal history | **No general API** | Notification mirroring and exposed quick-reply actions are the portable cross-app option. Each service's own API, if any, would be a separate integration. |
| Android camera in the Mac app | **Yes** | Camera/microphone are while-in-use permissions. The user must initiate the camera foreground service from visible UI, and Android shows privacy/foreground indicators. [Foreground-service restrictions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start), [foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types) |
| Android as a selectable Mac webcam | **Yes** | The Mac app can package a Core Media I/O camera extension, which requires system-extension activation/approval. [Apple camera extensions](https://developer.apple.com/documentation/coremediaio/creating-a-camera-extension-with-core-media-i-o) |
| Carrier-call relay | **Poor general fit** | Call-log/SMS data is restricted, and third-party access to live carrier-call audio is not a portable consumer API. Treat call relay as out of scope for an initial product. |

## Mirroring and control

### Public-API implementation

The Android app can capture a display through `MediaProjection`, feed frames into hardware encoding, and send the encoded stream over a low-latency local transport. A foreground service owns the active session. The Mac decodes and renders the frames in a dedicated native window. WebRTC is a strong media-plane choice because it already handles encrypted real-time media, congestion, jitter, and changing Wi-Fi conditions.

For control, normalized pointer coordinates and actions return over an encrypted control channel. An enabled Android Accessibility service can dispatch gestures and global Back/Home/Recents actions. Editable accessibility nodes can accept set-text actions. This will work for a large amount of ordinary UI, but it cannot promise correct behavior in every app or on every OEM build. [AccessibilityService API](https://developer.android.com/reference/android/accessibilityservice/AccessibilityService), [AccessibilityNodeInfo API](https://developer.android.com/reference/android/view/accessibility/AccessibilityNodeInfo)

### Unavoidable UX

For a fresh or ended session, the honest consumer flow is:

1. Click **Mirror** on Mac.
2. The phone surfaces a local notification or is already open.
3. The user approves Android's screen-capture system prompt.
4. Mirroring starts and can reconnect while that projection session remains active.

Android 14+ treats the token as one-time and requires consent for every capture session. A background app also cannot freely pop an activity over whatever the user is doing, so “click Mac and silently start forever” is not a public-API contract. [Android 14 MediaProjection changes](https://developer.android.com/about/versions/14/behavior-changes-14#media-projection), [background activity restrictions](https://developer.android.com/guide/components/activities/background-starts)

Protected content can appear black, and the OS or user can revoke capture. Screen audio may be absent where the source app disallows playback capture. The UI should state these as platform privacy behavior rather than connection failures. [MediaProjection capture behavior](https://developer.android.com/media/platform/av-capture)

## Discovery, pairing, and transport

There is no reason to expose IP addresses in the normal flow.

1. Both apps advertise and browse a dedicated DNS-SD service over mDNS (`NsdManager` on Android and `NWBrowser`/Bonjour on macOS).
2. The apps display friendly device names.
3. Pairing uses a QR code or short authenticated code, with approval on both devices.
4. Each side stores a long-term device key in Android Keystore or macOS Keychain and uses mutual authentication for future sessions.

Android 17 requires `ACCESS_LOCAL_NETWORK` for broad LAN communication by apps targeting API 37, with picker-mediated alternatives for selected discovery flows. macOS has enforced local-network privacy since macOS 15. The onboarding should explain this permission before triggering it. [Android 17 changes](https://developer.android.com/about/versions/17/behavior-changes-17#local-network), [Apple local-network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)

A sensible split is:

- **Control/events:** persistent TLS connection or secure WebSocket.
- **Screen/camera/audio:** WebRTC media channels.
- **Files:** resumable HTTP transfer with size, checksum, cancellation, and backpressure rather than sharing the latency-sensitive media queue.

Guest Wi-Fi and corporate networks may block peer discovery or isolate clients. QR pairing removes discovery ambiguity but cannot defeat network client isolation; a later relay service or a phone-hotspot fallback is needed if off-LAN operation becomes a goal.

## Files, clipboard, notifications, and messages

The file experience should be permission-scoped rather than pretending Android exposes a universal filesystem:

- Android **Share to Mac** accepts content URIs from the system Sharesheet.
- Mac drag-and-drop sends files to an app inbox, after which Android uses the system file picker or an authorized folder to save them.
- Optional folder grants through `ACTION_OPEN_DOCUMENT_TREE` support recurring sync without `MANAGE_EXTERNAL_STORAGE`.
- Large transfers are resumable and integrity-checked.

For clipboard, Mac-to-Android delivery can be explicit, but Android-to-Mac cannot be a completely passive background listener on modern Android. Start with share actions and a visible “Send clipboard” action. An optional custom IME can later make text handoff more automatic for users willing to enable it.

For communications, begin with Notification Access and quick replies through the actions each notification exposes. That supports many messaging apps without impersonating them or reading private databases. A full SMS surface should be a later, separately reviewed capability. Do not promise a unified historical inbox for RCS, WhatsApp, Signal, and similar services.

## Camera modes

Two distinct products can share the same transport:

1. **Remote camera:** show a selected Android lens in the Mac app, with capture and focus controls where CameraX/device support permits.
2. **Mac webcam:** feed the received frames into a Core Media I/O camera extension so FaceTime, Zoom, Meet, and other camera clients can select it.

The second mode is more valuable but has extra macOS lifecycle, system-extension, frame-sharing, and approval work. It should follow a proven direct camera stream rather than be the first media spike.

## What the open-source projects contribute

### scrcpy

scrcpy 4.1 is Apache-2.0 and reports high performance, including 30–120 fps and low latency. It mirrors and controls over USB or TCP/IP, but it uses ADB to push and execute a server as Android's `shell` user. Wireless use therefore still requires ADB TCP/IP or Android Wireless Debugging pairing. Its internal client/server protocol is explicitly unstable between versions. [scrcpy README](https://github.com/Genymobile/scrcpy), [connection guide](https://github.com/Genymobile/scrcpy/blob/master/doc/connection.md), [developer guide](https://github.com/Genymobile/scrcpy/blob/master/doc/develop.md)

Use scrcpy as:

- a latency and quality benchmark;
- a reference for codec, orientation, keyboard, and control edge cases;
- optionally, a clearly labeled advanced mode for users who accept Wireless Debugging.

Do not make it the only path if zero developer settings and zero terminal are core promises.

### KDE Connect

KDE Connect demonstrates the right product decomposition: discovery/pairing plus independent plugins for sharing, notifications, clipboard, commands, and other capabilities. Its desktop repository is GPLv2/GPLv3. Reusing or deriving from its implementation therefore has product-licensing consequences, especially for a proprietary app. [KDE Connect repository and license](https://github.com/KDE/kdeconnect-kde)

Use KDE Connect as architectural and UX inspiration. A direct fork is most attractive only if the intended product is GPL-compatible/open source and the team accepts substantial Mac-specific UI work. For a proprietary Mac-native product, a clean implementation of the needed concepts is the safer default; this is a product/legal decision, not legal advice.

## Recommended product direction

Build a native, local-first public-API core:

- Kotlin/Compose companion on Android.
- SwiftUI macOS shell with a normal main window, a small menu-bar status surface, and separate mirroring/camera windows.
- Bonjour/NSD discovery with QR fallback.
- Pair-once device identity and encrypted capability channels.
- MediaProjection + hardware encoding + WebRTC for view-only mirroring first.
- Accessibility control only as an explicit opt-in.
- Sharesheet/file-picker transfers and notification quick replies before broad storage or SMS permissions.
- Camera streaming first; Core Media I/O virtual camera second.
- Optional scrcpy/ADB “advanced mode” only after the consumer route works.

This route cannot remove Android's system consent screens, but it can remove every avoidable piece of friction: terminal commands, IP addresses, accounts, cloud routing on the same LAN, repeated device selection, ambiguous permissions, and fragile manual reconnection.
