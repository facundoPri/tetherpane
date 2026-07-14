# Apple continuity capabilities relevant to TetherPane

Research date: 2026-07-13  
Scope: current, practical iPhone-to-Mac capabilities. Sources are limited to Apple Support, Apple user guides, and Apple Platform Security.

## Executive summary

Apple's iPhone-Mac experience is a collection of specialized capabilities, not one all-purpose link:

- AirDrop handles explicit nearby transfers.
- Handoff and Universal Clipboard move an activity or a small piece of content between nearby devices.
- iPhone Mirroring provides interactive remote control, with file drag-and-drop and a separately persistent notification bridge.
- AirPlay to Mac is view/stream only; it does not control the iPhone.
- Continuity Camera exposes the iPhone as a webcam/microphone or invokes it for a one-off photo/document scan.
- Cellular calls and carrier messages are relayed through the iPhone, while iMessage and Messages in iCloud add cloud-backed synchronization.
- Instant Hotspot exposes the iPhone's cellular data connection to the Mac.

The architectural lesson is important: "same Wi-Fi" is not Apple's whole model. Apple commonly combines Bluetooth Low Energy for proximity discovery, an Apple Account for device trust, direct peer-to-peer Wi-Fi for bulk data, TLS or message-level encryption, and Apple cloud services for selected remote events. Some features require the same access point; AirDrop specifically does not. [Apple Platform Security: Continuity](https://support.apple.com/guide/security-pdf/continuity-security-overview-secce267dc10/web), [AirDrop security](https://support.apple.com/guide/security/airdrop-security-sec2261183f4/web), [Handoff security](https://support.apple.com/en-euro/guide/security/secf78dbe639/web)

## Core capabilities

| Capability | Practical experience | Current requirements and limits |
| --- | --- | --- |
| **AirDrop** | Bidirectional transfer of photos, videos, documents, websites, locations, and other share-sheet items. Same-account transfers are automatically accepted; other transfers are accepted or declined by the recipient. | Wi-Fi and Bluetooth must be on, and devices are normally within 30 feet / 10 m. AirDrop uses BLE discovery and direct peer-to-peer Wi-Fi, so the devices do not need to share an access point or internet connection; the direct transfer is TLS-encrypted. Current Apple guidance says that after a transfer starts it can continue over the internet if the devices leave local range. Receiving is Contacts Only, Everyone for 10 Minutes, or Off. Current OS 26.2 releases add an AirDrop code for non-contacts. Apple positions AirDrop for a small selection of files rather than bulk synchronization. [Use AirDrop](https://support.apple.com/en-lamr/guide/iphone/iphcd8b9f0af/ios), [AirDrop security](https://support.apple.com/guide/security/airdrop-security-sec2261183f4/web) |
| **Handoff** | Begin a supported activity on one device and resume it on the other. Apple examples include Safari, Mail, Maps, Messages, and FaceTime; third-party apps can implement Handoff too. It can also move an in-progress FaceTime call. | Devices must be nearby, signed into the same Apple Account, and have Wi-Fi, Bluetooth, and Handoff enabled. Handoff is application-level continuity, not general remote control. Baseline support is iOS 8 / OS X Yosemite on Apple's listed hardware; FaceTime call handoff needs iOS 16 and macOS Ventura 13. [Handoff guide](https://support.apple.com/guide/mac-help/hand-off-tasks-between-devices-mchl732d3c0a/26/mac/26), [Continuity requirements](https://support.apple.com/en-us/108046) |
| **Universal Clipboard** | Copy content on iPhone and paste on Mac, or the reverse. Apple explicitly lists text, images, photos, and videos, and its workflow also refers to files or other supported content. The shared clipboard exists only briefly. | Same Apple Account, nearby devices, Wi-Fi, Bluetooth, and Handoff are required. Baseline support is iOS 10 and macOS Sierra 10.12 on Apple's listed hardware. Apple says it is best for small selections; AirDrop, iPhone Mirroring drag-and-drop, iCloud Drive, or device sync are better models for deliberate or multi-file transfer. [Universal Clipboard](https://support.apple.com/en-us/102430), [Mac clipboard guidance](https://support.apple.com/guide/mac-help/copy-and-paste-between-devices-mchl70368996/mac) |
| **iPhone Mirroring** | Wirelessly view and control the entire iPhone from a Mac while the phone stays locked. The Mac's pointer/trackpad performs touch gestures, the keyboard types into iPhone apps, iPhone audio plays through the Mac, and the window changes orientation where an app requires it. Supported apps allow bidirectional drag-and-drop, including between the iPhone Files app and the Mac. | iOS 18+, a passcode-enabled iPhone, and macOS Sequoia 15+ on Apple silicon or an Intel Mac with the T2 chip. Both devices use the same Apple Account with 2FA, Wi-Fi and Bluetooth are on, and the iPhone is locked and nearby. Only one iPhone and one Mac can be active at a time. Unlocking the iPhone ends the session. The Mac cannot simultaneously share its internet connection or use AirPlay or Sidecar. The iPhone camera, microphone, Face ID, and phone calls are unavailable inside Mirroring; premium streaming video can be restricted by its provider. Apple currently says iPhone Mirroring is unavailable in the European Union. [iPhone Mirroring](https://support.apple.com/en-us/120421) |
| **iPhone notifications on Mac** | Once iPhone Mirroring has paired the devices, iPhone notifications appear on the Mac with an iPhone badge. Clearing one on iPhone clears its mirrored copy on Mac. Clicking a notification while the phone is nearby opens the corresponding iPhone app through Mirroring. Live Activities can appear in the Mac menu bar. | The initial iPhone Mirroring setup is mandatory. After that, the Mirroring window can be closed and the iPhone does not need to remain nearby; it must remain turned on. Users can disable the bridge globally or per iPhone app, and revoke a Mac from the iPhone. Live Activities require macOS Tahoe 26+. [Notification and Live Activity guide](https://support.apple.com/en-us/120684) |
| **AirPlay to Mac** | Streams media or visually mirrors the iPhone screen onto a Mac. This is the noninteractive alternative Apple recommends where iPhone Mirroring is unavailable. | Normal use expects the same Wi-Fi network and an enabled AirPlay Receiver on the Mac. Apple's full-resolution baseline is iPhone 7 / iOS 14 and supported 2018-era-or-newer Macs / macOS Monterey 12; some older combinations work at lower resolution. AirPlay does not provide pointer, keyboard, or touch control of the phone. [Continuity requirements: AirPlay to Mac](https://support.apple.com/en-us/108046), [AirPlay troubleshooting and network requirements](https://support.apple.com/en-us/102587) |

## Camera and capture

### Continuity Camera as webcam and microphone

An iPhone can appear as a camera and, where applicable, a microphone in Mac apps that use standard camera or audio inputs. It works wirelessly or over USB and exposes Apple effects such as Center Stage, Portrait mode, Studio Light, and Desk View when the hardware supports them. This is a system camera source, not a screen-mirroring mode. Privacy indicators appear on iPhone and Mac while the camera or microphone is in use. [Continuity Camera webcam guide](https://support.apple.com/en-mide/102546)

The current baseline is iPhone XR or later with iOS 16+, plus any Mac capable of macOS Ventura 13+. The devices must be nearby, signed into the same Apple Account with 2FA, and have Bluetooth and Wi-Fi on. The iPhone cannot be sharing its cellular connection, the Mac cannot be sharing its internet connection, and wireless use conflicts with AirPlay and Sidecar. USB use requires the iPhone to trust the Mac. Apple supports one iPhone-Mac pair at a time. [Continuity Camera requirements](https://support.apple.com/en-mide/102546), [Continuity feature matrix](https://support.apple.com/en-us/108046)

### Continuity Camera for photos and document scans

A supported Mac app can invoke the nearby iPhone camera for a one-off photo or multi-page document scan. The photo is inserted directly; scans arrive as a PDF. Apple lists Finder, Freeform, Keynote, Mail, Messages, Notes, Numbers, Pages, and TextEdit among the built-in supported Mac apps. [Photo and document scan guide](https://support.apple.com/en-gb/102332)

This older, lighter-weight flow has a different baseline: iOS 12+, macOS Mojave 10.14+, and Apple's listed 2012/2013/2015-or-later Mac models. Both devices need Wi-Fi and Bluetooth enabled and the same Apple Account with 2FA. It is a task invocation, not a persistent webcam or a general live camera viewer. [Photo and document scan requirements](https://support.apple.com/en-gb/102332)

## Communications

### iPhone cellular calls on Mac

After enabling Calls on Other Devices, a Mac can make and answer carrier calls relayed through the iPhone. Users can dial from the Phone app on current macOS or click numbers in Contacts, Calendar, Messages, Spotlight, Safari, and other apps. Incoming calls surface as Mac notifications. [Calls and text relay guide](https://support.apple.com/guide/iphone/phone-calls-text-messages-ipad-mac-iphf90f372f0/ios)

The baseline relay requires the same Apple Account, FaceTime configured with the same account and phone number, the same Wi-Fi network, and proximity to the iPhone. The iPhone needs an activated carrier plan; normal carrier charges apply. Mac mini, Mac Studio, and Mac Pro need an external microphone or headset. Apple's security guide says notifications use APNs with iMessage-like end-to-end protection and the call audio uses a secure peer-to-peer connection. Carrier-supported Wi-Fi Calling on other devices is a separate extension and is not universally available. [Continuity requirements: cellular calls](https://support.apple.com/en-us/108046), [Cellular call relay security](https://support.apple.com/en-sa/guide/security/sec28a79bf17/web), [Wi-Fi Calling](https://support.apple.com/en-mide/108066)

### iMessage and SMS/MMS/RCS on Mac

The Messages app on Mac supports iMessage directly. Text Message Forwarding additionally makes SMS, MMS, and RCS sent or received through the iPhone appear on Mac, and replies go back through the iPhone. Messages in iCloud keeps the whole history synchronized and incorporates Text Message Forwarding automatically; otherwise, the user explicitly authorizes each Mac in iPhone settings. [Text Message Forwarding](https://support.apple.com/en-ie/102545)

Devices use the same Apple Account, and the iPhone must be on, online via Wi-Fi or cellular, and able to send and receive messages. Two-factor authentication makes device enrollment automatic; otherwise Apple uses a six-digit verification code. SMS/MMS/RCS require an activated carrier plan. RCS specifically requires iOS 18 and a carrier and region that support RCS on iPhone; its availability and charges vary. [Text forwarding security](https://support.apple.com/guide/security/iphone-text-message-forwarding-security-sec16bb20def/web), [RCS requirements](https://support.apple.com/en-us/122195)

## Internet sharing

Personal Hotspot turns the iPhone's carrier data connection into a temporary Wi-Fi network for the Mac; USB and Bluetooth connection modes also exist. Instant Hotspot is the seamless layer: a nearby Mac signed into the same Apple Account, or in the same Family Sharing group, discovers and joins the hotspot more quickly without the ordinary password workflow. [Personal Hotspot](https://support.apple.com/en-us/111785)

Both devices need Wi-Fi and Bluetooth on and must be nearby. The iPhone needs a carrier plan that supports Personal Hotspot; fees and simultaneous-device limits can vary by carrier and iPhone model. Apple says Instant Hotspot discovers trusted devices over BLE and encrypts the request and connection-information exchange. This feature supplies internet access; it is not a general-purpose device-to-device file bridge. [Continuity requirements: Instant Hotspot](https://support.apple.com/en-us/108046), [Instant Hotspot security](https://support.apple.com/en-mide/guide/security/seca4b33e8c9/web)

## Secondary conveniences worth knowing about

These are real iPhone-Mac capabilities, but they are less central to TetherPane's stated problem:

- **iPhone widgets on Mac:** macOS Sonoma 14+ can display widgets from an iOS 17+ iPhone without installing the corresponding Mac app. Interacting with one can open the iPhone app in iPhone Mirroring on current systems. [Continuity feature matrix](https://support.apple.com/en-us/108046), [Mac iPhone Mirroring guide](https://support.apple.com/guide/mac-help/control-your-iphone-from-your-mac-mchl444d53a6/26/mac/26)
- **Continuity Sketch and Markup:** use iPhone or iPad to draw a sketch or mark up a Mac document and see the result on Mac. Baseline support is iOS 13 / macOS Catalina on Apple's listed hardware. [Continuity feature matrix](https://support.apple.com/en-us/108046)
- **Apple Pay approval:** a Mac can begin an online purchase and use a nearby iPhone or Apple Watch to complete Apple Pay authorization. This is an authentication handoff, not device control. [Continuity feature matrix](https://support.apple.com/en-us/108046)
- **Finder file sharing and synchronization:** Finder can copy files to and from iPhone apps that expose File Sharing. Finder also supports same-Wi-Fi device synchronization after the user performs an initial USB/USB-C setup and enables “Show this device when on Wi-Fi.” It is slower than cable sync and is a managed sync/device-management path rather than a spontaneous AirDrop-like experience. [Finder file sharing](https://support.apple.com/en-lamr/119585), [Finder Wi-Fi sync](https://support.apple.com/en-ie/guide/mac-help/mchlada1d602/mac)
- **iCloud synchronization:** iCloud Drive, Photos, Messages, and app-specific iCloud data keep content synchronized across devices through Apple's cloud. This is broader than local continuity and has different storage, account, and network tradeoffs. [Apple's syncing overview](https://support.apple.com/guide/mac-help/syncing-overview-mchl923c1147/mac)

## Important non-iPhone distinctions

- **Sidecar is iPad-only.** It uses an iPad as a second display that extends or mirrors the Mac desktop, optionally with Apple Pencil input. The direction is Mac to iPad; it is not iPhone remote control. [Continuity feature matrix: Sidecar](https://support.apple.com/en-us/108046)
- **Universal Control is Mac-and-iPad only.** It lets one Mac keyboard, mouse, or trackpad control nearby Macs and iPads. It does not control an iPhone. [Continuity feature matrix: Universal Control](https://support.apple.com/en-us/108046)
- **Auto Unlock is Apple Watch to Mac, not iPhone to Mac.** [Continuity feature matrix: Auto Unlock](https://support.apple.com/en-us/108046)
- **Mac Virtual Display and Mirror My View are Apple Vision Pro features.** They are not iPhone-Mac continuity analogues. [Continuity feature matrix](https://support.apple.com/en-us/108046)

## Cross-cutting trust, proximity, and safety patterns

1. **Discovery and transport are separate.** AirDrop and Handoff begin with BLE discovery/advertising. Larger Handoff payloads and AirDrop data then move over Apple-created peer-to-peer Wi-Fi, with TLS used for the high-bandwidth connection. A shared home router is therefore not necessary for every Apple feature. [AirDrop security](https://support.apple.com/guide/security/airdrop-security-sec2261183f4/web), [Handoff security](https://support.apple.com/en-euro/guide/security/secf78dbe639/web)
2. **Account trust removes repeated pairing friction.** Most personal continuity features require the same Apple Account, and security-sensitive features commonly require 2FA. AirDrop is the notable social-sharing exception: it can connect different accounts, using Contacts-based identity or a temporary non-contact mode/code. [Continuity Camera requirements](https://support.apple.com/en-mide/102546), [AirDrop security](https://support.apple.com/guide/security/airdrop-security-sec2261183f4/web)
3. **Ten metres is the practical nearby envelope.** Apple explicitly documents 30 feet / 10 m for AirDrop, Universal Clipboard, iPhone Mirroring, and calls/text troubleshooting. Camera documentation says “nearby” without a separate longer range. [AirDrop guide](https://support.apple.com/en-lamr/guide/iphone/iphcd8b9f0af/ios), [Mac Universal Clipboard guide](https://support.apple.com/guide/mac-help/copy-and-paste-between-devices-mchl70368996/mac), [Mac iPhone Mirroring guide](https://support.apple.com/guide/mac-help/control-your-iphone-from-your-mac-mchl444d53a6/26/mac/26)
4. **Some bridges persist after local pairing.** Mirrored notifications continue when the iPhone is no longer nearby, provided it is on. Messages in iCloud synchronizes history over the cloud. This differs from live screen control, camera, clipboard, and ordinary cellular call relay, which are proximity/local-link experiences. [Notification guide](https://support.apple.com/en-us/120684), [Text Message Forwarding](https://support.apple.com/en-ie/102545)
5. **User-visible revocation and state are part of the experience.** iPhone Mirroring records which Mac connected and for how long, allows access revocation, pauses after inactivity, and can require Mac authentication each time. Notification mirroring is controllable globally and per app. AirDrop asks recipients to accept transfers except for the user's own same-account devices. [iPhone Mirroring](https://support.apple.com/en-us/120421), [Notification guide](https://support.apple.com/en-us/120684), [AirDrop guide](https://support.apple.com/en-lamr/guide/iphone/iphcd8b9f0af/ios)

## Product-relevant conclusions

- Apple's closest analogue to the desired TetherPane experience is not AirDrop alone; it is the combination of iPhone Mirroring, mirrored notifications, AirDrop, Universal Clipboard, Continuity Camera, message/call relay, and account-based pairing.
- A credible Android-Mac equivalent should treat discovery, authentication, control input, real-time media, bulk transfer, clipboard, and background notifications as separate services behind one paired-device experience.
- “No IP address” discovery is achieved through local service discovery/proximity signaling, while a trusted device identity eliminates repeated manual connection steps.
- Wi-Fi mirroring needs an explicit concurrency/resource policy. Apple blocks combinations such as Mirroring with AirPlay/Sidecar and Continuity Camera with AirPlay/Sidecar, and it limits live use to one phone-Mac pair.
- Security is visible, not merely cryptographic: initial consent, locked-device behavior, authentication choice, connection history, per-feature permissions, per-app notification controls, and easy revocation all contribute to the feeling of a safe seamless bridge.

## Primary source index

- [Apple continuity features and system requirements](https://support.apple.com/en-us/108046)
- [iPhone Mirroring](https://support.apple.com/en-us/120421)
- [iPhone notifications and Live Activities on Mac](https://support.apple.com/en-us/120684)
- [Continuity Camera as webcam](https://support.apple.com/en-mide/102546)
- [Continuity Camera photo and scan](https://support.apple.com/en-gb/102332)
- [Use AirDrop](https://support.apple.com/en-lamr/guide/iphone/iphcd8b9f0af/ios)
- [Universal Clipboard](https://support.apple.com/en-us/102430)
- [Calls and messages on Mac](https://support.apple.com/guide/iphone/phone-calls-text-messages-ipad-mac-iphf90f372f0/ios)
- [Text Message Forwarding](https://support.apple.com/en-ie/102545)
- [Personal Hotspot](https://support.apple.com/en-us/111785)
- [Apple Platform Security: Handoff](https://support.apple.com/en-euro/guide/security/secf78dbe639/web)
- [Apple Platform Security: AirDrop](https://support.apple.com/guide/security/airdrop-security-sec2261183f4/web)
- [Apple Platform Security: cellular call relay](https://support.apple.com/en-sa/guide/security/sec28a79bf17/web)
- [Apple Platform Security: text forwarding](https://support.apple.com/guide/security/iphone-text-message-forwarding-security-sec16bb20def/web)
- [Apple Platform Security: Instant Hotspot](https://support.apple.com/en-mide/guide/security/seca4b33e8c9/web)
