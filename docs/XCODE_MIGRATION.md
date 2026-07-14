# Xcode-native migration

TetherPane now has a real macOS application target in `TetherPane.xcodeproj`. The migration deliberately keeps one copy of each source file:

- Xcode owns the application bundle, shared scheme, app icon, privacy manifest, hardened runtime, signing settings, Run/Profile/Analyze/Archive actions, and the SwiftUI application sources under `Sources/AirDroidMac`.
- The Xcode app target consumes `AirDroidDomain` and `AirDroidScrcpy` as local Swift package products. Those modules remain the stable domain and stock-scrcpy adapter seams.
- SwiftPM keeps the command-line build and deterministic seam-test runner available while the local machine has only Command Line Tools.

This is an incremental native migration, not a second implementation.

## Open and run

1. Install the current full Xcode release and select it:

   ```bash
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   ```

2. Open `TetherPane.xcodeproj`.
3. Select the shared `TetherPane` scheme and **My Mac** destination.
4. Add the maintainer's Apple Development or Developer ID team in Signing & Capabilities when signing is needed.
5. Run with `⌘R`, or validate from the repository root:

   ```bash
   make xcode-project-test
   ```

`script/package_macos.sh` prefers the Xcode scheme when full Xcode is selected and falls back to SwiftPM on a Command Line Tools-only machine. Use `--build-system xcode` or `--build-system swiftpm` to force a path while diagnosing a build.

## Remaining migration work

The project is Xcode-native for app development and archives, but two cleanup steps remain before calling SwiftPM compatibility optional:

1. Add an XCTest target and migrate the executable seam contracts once the full Xcode toolchain is available on every maintainer machine. Tests should continue crossing only the domain and adapter interfaces described in `CONTEXT.md`.
2. Rename the internal pre-public module and source-directory names (`AirDroidDomain`, `AirDroidScrcpy`, and `AirDroidMac`) in one mechanical, separately reviewed change. They are not user-visible and remain unchanged now to keep the release migration small and auditable.

Do not move source files into duplicate Xcode-only directories. A source file must be owned by one module even when both Xcode and SwiftPM can build it.
