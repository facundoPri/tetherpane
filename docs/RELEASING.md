# macOS release runbook

The native `TetherPane` scheme owns the macOS application target, app icon catalog, bundle settings, privacy manifest, hardened runtime, and Archive action. The app target consumes the existing SwiftPM domain and scrcpy adapter products as local package dependencies. The checked-in release scripts keep signing, notarization, archive creation, and independent verification reproducible outside the Xcode UI.

## Public-release blockers

Do not publish the first public build until all of these are resolved:

1. Complete a formal trademark check for the working **TetherPane** name before a commercial 1.0 release. The exact-name web and GitHub screen is not legal clearance.
2. Choose the stable-user dependency path for stock scrcpy 4.1 and `adb`. The beta documents Homebrew; the recommended stable path bundles the checksum-pinned official release described in `docs/SCRCPY_DISTRIBUTION.md`.
3. Install full Xcode and select it with `xcode-select`; Command Line Tools alone cannot validate the native scheme or produce the tested universal archive on the current machine.
4. Obtain a valid **Developer ID Application** certificate and Apple notarization credentials. Keep certificates, passwords, and App Store Connect keys outside Git.
5. Complete the remaining physical-phone acceptance matrix and repeat it against the exact signed and notarized candidate archive.

The signed app is the responsible code for local-network operations performed by its spawned `adb` process. Preserve `NSLocalNetworkUsageDescription` and all three declared ADB Bonjour service types when renaming or regenerating bundle metadata, then test both Allow and Don’t Allow paths from a fresh macOS user account or VM.

## Local release candidate

Create and verify an Apple-silicon, hardened, ad-hoc-signed candidate:

```bash
make macos-release VERSION=0.1.0 BUILD_NUMBER=1 ARCHITECTURE=native
make macos-release-test
```

Outputs:

- `dist/release/TetherPane.app`
- `dist/release/TetherPane-0.1.0-macos.zip`

The ad-hoc artifact is for local QA only. It is expected to fail Gatekeeper assessment because it has no Developer ID trust chain or notarization ticket.

## Signed and notarized direct distribution

Create a reusable `notarytool` keychain profile according to Apple’s notarization documentation, then run:

```bash
make macos-release \
  VERSION=1.0.0 \
  BUILD_NUMBER=1 \
  ARCHITECTURE=universal \
  SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
  NOTARY_PROFILE=product-notary
```

The release command:

1. builds the native Xcode scheme when full Xcode is selected, otherwise the SwiftPM compatibility executable;
2. stages or copies the standard `Contents/MacOS`, `Contents/Resources`, and `Info.plist` layout;
3. signs with hardened runtime and a secure timestamp;
4. verifies the sealed bundle and absence of `get-task-allow`;
5. creates a ZIP with `ditto`;
6. submits it with `notarytool`, waits for the result, staples the ticket, recreates the ZIP, and runs Gatekeeper assessment.

Never publish an asset if notarization, stapling, `codesign --verify --deep --strict`, or `spctl -a -vv --type execute` fails.

## GitHub release sequence

1. Review every tracked file for credentials, device identifiers, private acceptance artifacts, and obsolete public branding.
2. Push source first and require the macOS and Android `CI` jobs on the default branch.
3. Keep force pushes and deletion disabled, require pull requests and resolved conversations, and enable Dependabot alerts, automated security fixes, secret scanning, push protection, and private vulnerability reporting.
4. Create a signed tag such as `v1.0.0` from a reviewed commit.
5. Build/notarize from that exact tag, calculate a SHA-256 checksum for the final ZIP, and attach both to a GitHub Release.
6. Test the downloaded, quarantined artifact on a second Mac account or clean Mac before marking the release stable.

Do not upload `dist/` through normal commits; release artifacts belong on GitHub Releases.
