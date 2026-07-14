# One-device control center acceptance — 2026-07-14

Scope: the native SwiftUI control center hierarchy, typed connection presentation, asynchronous ADB orchestration, and exact-endpoint stock scrcpy 4.1 safety contract.

## Automated evidence

- `make macos-test` passes 49 deterministic macOS seam contracts; earlier full-scope acceptance also passed the Android local unit-test task, `make macos-build`, `make doctor`, shell syntax checks, and `git diff --check`.
- The new `ConnectionCoordinator` contracts cover disconnected, USB authorization, USB ready, legacy enabling, exact safe-to-unplug provenance, nearby secure wireless, pairing, secure ready, mirroring, scoped recovery, unclassified wireless, stale async discovery rejection, partial mDNS failure, mirror stop, and ambiguous secure endpoint association.
- Existing scrcpy 4.1 contracts still assert the literal exact `--serial=<selected-endpoint>` argument and the pinned Responsive/High Quality, audio, recording, lifecycle, diagnostics, and stop/reconnect behavior.
- `ADBDeviceDiscovery` now returns USB device results even when `adb mdns services` fails, with a wireless-only warning.
- Discovery, wireless ADB operations, and scrcpy process launch/termination run outside the main actor. Parent tasks are cancellable, generation tokens reject late discovery completions before live store state mutates, and the same scoped tokens prevent deferred verification from an older wireless action from associating its endpoint after a newer action starts.
- `ConnectionEndpointClassifier` tests exact IPv6 formatting, current secure-service precedence, unclassified-route safety, and explicit app-initiated legacy provenance without IP-suffix inference.
- `DeviceDirectory` tests connected-to-offline retention, observed ADB-offline presentation, same-name exact-serial separation, exact secure-service grouping, persisted local suppression, session-only unclassified-endpoint suppression, defensive persisted-record restore, and exact-route rejection in the wireless disconnect adapter.
- `ConnectionCoordinator` tests selected-endpoint priority so a separately verified legacy route for phone A cannot replace the workspace for selected phone B, while successful USB-assisted setup still moves exact selection from the source USB serial to its freshly verified wireless serial.

## UI-visible contract

- A native source list separates **Devices**, **Offline**, and **Connect**. It keeps saved phones recognizable when they are not currently reachable.
- **USB-C · Automatic** and **Wi-Fi Only · Wireless Debugging** are the only persistent connection choices in the sidebar.
- Unauthorized USB exposes only unlock-and-Allow guidance.
- An authorized endpoint exposes one prominent **Mirror** or **Stop Mirroring** action. An always-visible **Mirror settings** card uses a native segmented quality picker plus native audio and next-session recording toggles; it switches from a compact horizontal row to a vertical layout when the inspector narrows the workspace.
- A route-specific **Connection** card keeps transport, security, lifecycle, and the honest route action together: unplug for USB-C, local disconnect for secure Wireless Debugging, Turn Off for unencrypted Wi-Fi-until-restart, and exact-endpoint local disconnect for an unverified route.
- One wireless sheet contains secure Wireless Debugging and consent-gated USB-assisted Wi-Fi.
- Secure wireless exposes **Disconnect on This Mac** and retains a locally suppressed offline row while explicitly stating that Android authorization is unchanged. USB requires unplugging; proven legacy Wi-Fi retains its safety-specific **Turn Off** action.
- Offline devices offer reconnect guidance and **Forget from List** only as local list management, never as an Android unpair or authorization revocation claim.
- The selected exact USB endpoint controls both wireless actions; same-name multi-USB ambiguity requires physically leaving one phone attached instead of silently choosing.
- Legacy mode stays on **Keep the cable connected** until a fresh discovery proves the exact returned wireless serial is authorized; only then does it say the cable can be removed.
- No IP address is persisted as identity. A consented setup saves only its exact USB source as a conservative possible-listener risk, keeps competing wireless work disabled until the operation settles, and preserves a USB-based protective Turn Off path after interruption or relaunch.
- Scoped failures expose an actionable Refresh, Wireless Setup, or Reconnect control in the workspace. Manual discovery reports progress while periodic background polling stays quiet.
- If the recording destination cannot be prepared, mirroring continues safely without recording and a visible warning replaces the completed start progress so the fallback cannot be mistaken for an active recording.
- Exact serials for every visible ADB endpoint, mDNS host/ports, tool paths, invocation arguments, exit status, and process output live in Advanced.
- Motion is limited to critically damped state replacement and is disabled under Reduce Motion. The UI uses a native source list, sheet, inspector, forms, controls, and system materials rather than custom glass chrome. Refresh and Advanced Details have stable sidebar Utility rows; Advanced also has an inspector-local close control and no one-item toolbar overflow.

## Physical-device acceptance

An authorized Motorola edge 40 pro appeared during final acceptance as a single live USB endpoint. Its serial is redacted from this public acceptance record.

- `adb devices -l` reported only `<redacted-usb-serial>` as `device usb:… model:motorola_edge_40_pro` immediately before use.
- An initial read-only readiness check reported `service.adb.tcp.port = 0`, `adb_wifi_enabled = 0`, and no advertised mDNS services. This proved no legacy listener was left open. Android later enabled Wireless Debugging outside the Mac app: `adb_wifi_enabled` became `1`, the classic TCP/IP port remained `0`, and `_adb-tls-connect._tcp` appeared. TetherPane did not toggle either Android setting.
- The foreground control center presented that same phone as **USB · Ready**.
- Choosing **Mirror** launched the installed stock `/opt/homebrew/bin/scrcpy` 4.1 with the literal `--serial=<redacted-usb-serial>` plus the selected Responsive preset. Its child ADB server command used the same exact redacted serial.
- The UI changed to **Stop Mirroring** while that process was alive. Choosing it terminated both scrcpy and its child ADB server and returned the same USB endpoint to **Mirror**.
- Advanced showed the exact selected serial, Direct USB route, USB observation provenance, effective invocation, tool paths, and bounded scrcpy 4.1 output.
- **Open Developer Options on phone** targeted the exact authorized USB endpoint. The app reported success, and a read-only `dumpsys activity` check showed `com.android.settings/.Settings$DevelopmentSettingsActivity` foreground on `<redacted-usb-serial>`.
- With Android already advertising an authorized secure connection service, the new wireless sheet kept it unassociated until **Connect Nearby Connection** returned the exact authorized endpoint represented here by the documentation-only address `192.0.2.44:38883`. The Device Stage then showed **Secure Wireless · Ready** and Advanced showed **Observed secure mDNS connection service**.
- Secure Mirror launched stock scrcpy 4.1 with literal `--serial=192.0.2.44:38883`; its child used `adb -s 192.0.2.44:38883 ... com.genymobile.scrcpy.Server 4.1`. The UI exposed Stop Mirroring, and Stop returned the same secure endpoint to Mirror with bounded renderer/device output retained in Advanced.

Still required with the person holding the phone:

- Enable legacy mode with consent, keep USB attached until the app reports safe-to-unplug, physically unplug, then Mirror and Stop using the exact Wi-Fi endpoint.
- Physically unplug USB and repeat exact secure Wireless Debugging Mirror/Stop. The secure transport itself passed while USB remained attached, but no-cable acceptance is not inferred from endpoint selection.
- Open Android's fresh six-digit pairing dialog and complete fresh secure pairing. The already-authorized connect service does not prove recovery pairing.
- Confirm ambiguous endpoints are never merged into a claimed Physical Phone.

## UI inspection status

The final `.app` built and launched in the foreground through `./script/build_and_run.sh --verify`. Computer Use initially crashed while transforming the one-device accessibility tree. A temporary unchanged-`HEAD` comparison proved the tool and base app were healthy; a current-source probe narrowed the cycle to SwiftUI's labeled `GroupBox`. Replacing the three workspace group boxes with semantic native SwiftUI cards made the full final tree readable and kept the intended visual hierarchy.

Computer Use then read, interacted with, and captured the final app in these states:

- The new device-management fixture showed two connected phones on distinct USB-C and secure Wi-Fi routes, one saved offline phone, both connection choices, readable route subtitles, responsive Mirror placement, and route-specific disconnect guidance.
- A locally disconnected secure fixture showed **Disconnected on this Mac**, **Reconnect over Wi-Fi**, and honest Forget guidance while keeping Android authorization explicitly unchanged.
- An unclassified wireless fixture showed **Wi-Fi · Route unverified** and **Disconnect Unverified Endpoint**, limiting suppression to the app session and making no Android trust, security, or lifetime claim.
- The live foreground app showed `motorola edge 40 pro` under Devices as **USB-C · Connected**, with Mirror visible at the compact default window size. A final read-only check reported only the exact redacted USB serial, no advertised mDNS services, and no scrcpy process.

- Live authorized USB ready, Mirror, Stop, Advanced, consolidated Wireless Setup, secure guidance, and USB-assisted consent with its action disabled until consent.
- Unauthorized USB, same-name multi-USB ambiguity, distinguishable multi-USB chooser including switching to the second endpoint, partial mDNS failure with retained USB and Refresh recovery, and secure pairing.
- Inert reserved-address fixtures covered the new legacy-only Device Stage states without invoking ADB: **Keep the cable connected** exposed an accessible busy indicator and kept Turn Off disabled while unsettled; **Wi-Fi until restart · Unencrypted** announced verified safe-to-unplug success and exposed Mirror plus Turn Off.
- Advanced on the safe-to-unplug fixture showed the exact reserved endpoint `192.0.2.44:5555`, **USB-assisted Wi-Fi until restart**, and **Verified app-initiated USB transition** rather than inferring provenance from the `:5555` suffix.
- Every recognized UI fixture replaces pairing, wireless, mirroring, and legacy-risk persistence dependencies with inert or ephemeral implementations. Deliberate fixture Mirror and consented Enable clicks produced visible fixture-only failures, launched no process or reserved ADB connection, and left no `UserDefaults` legacy-risk key.
- The same-name ambiguity fixture's Advanced inspector exposed both raw exact serials (`ui-fixture-exact` and `ui-fixture-same-name-exact`) without assigning either to a physical identity.
- Secure pairing exposed a secure six-digit field, kept **Pair and Connect** disabled when empty, enabled it after a six-digit fixture value, and did not expose the code as plain accessibility text.
- The window zoom action expanded the layout to a wide desktop size without clipping or changing the one-device hierarchy, then restored the prior size.
- Escape dismissed the wireless sheet. The common `⌘⌥W` shortcut was verified from the live USB-ready state after making it consistent across every wireless-setup entry state.
- `⌘⌥M` started exact-endpoint mirroring and `⌘.` stopped it; the standard Window menu retained its native **Minimize** command instead of TetherPane overriding `⌘M`.
- Opening Developer Options now publishes operation feedback in the wireless sheet and temporarily disables repeated activation until the exact-device command settles.
- The refined live secure and USB panels exposed Mirror, the segmented quality picker, audio and recording toggles, the route security/lifecycle summary, and the route action at the default window size. Computer Use changed High Quality and recording through their native controls, observed the new values, and restored Responsive with recording off.
- The sidebar **Advanced Details** row opened the inspector without a toolbar overflow item; both the row and the inspector-local close button hid it again. At the narrower content width, Mirror settings automatically used its vertical fallback without losing any control.
- The inert safe-to-unplug fixture showed **Wi-Fi until restart**, **Unencrypted on your local network**, the visible **Turn Off USB-assisted Wi-Fi** action, and an orange turn-off warning in one Connection card. The inert unclassified fixture kept **Route unverified**, **Security not verified**, exact-endpoint disconnect, and the no-identity-inference warning together.

The current system uses Dark appearance, which was visually verified. Process-only command-line attempts did not override the system to Light appearance. Full Tab traversal is also disabled by the current macOS Full Keyboard Access setting. Light appearance, Full Keyboard Access traversal, Reduce Motion, and Reduce Transparency visual checks are therefore not claimed; changing those persistent system settings requires explicit confirmation. The implementation uses semantic colors/materials and removes its only state-replacement animation when SwiftUI reports Reduce Motion.
