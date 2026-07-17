# Xcode-native migration

TetherPane now has a real macOS application target in `TetherPane.xcodeproj`. The migration deliberately keeps one copy of each source file:

- Xcode owns the application bundle, shared scheme, app icon, privacy manifest, hardened runtime, signing settings, Run/Profile/Analyze/Archive actions, and the SwiftUI application sources under `Sources/AirDroidMac`.
- The Xcode app target consumes `AirDroidDomain` and `AirDroidScrcpy` as local Swift package products. Those modules remain the stable domain and stock-scrcpy adapter seams.
- Process-local visual-QA identifiers and presentation overrides live in the separate `TetherPaneUIFixtureSupport` package product, keeping fixture infrastructure out of the production device/session domain.
- SwiftPM keeps the command-line build and deterministic seam-test runner available when a maintainer machine selects only Command Line Tools.

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

The migration was accepted on 2026-07-14 with Xcode 26.6: `make xcode-project-test` built the shared Debug scheme, and `make macos-release VERSION=0.1.0 BUILD_NUMBER=1 ARCHITECTURE=native BUILD_SYSTEM=xcode SIGNING_IDENTITY=-` built and verified the Xcode Release application and versioned ZIP.

## Visual QA fixtures

`script/build_and_run.sh` can launch an inert fixture with process-local presentation overrides. This verifies alternate appearance and accessibility branches without changing persistent macOS settings or invoking ADB and scrcpy:

```bash
TETHERPANE_UI_FIXTURE=device-management \
TETHERPANE_UI_APPEARANCE=light \
TETHERPANE_UI_REDUCE_MOTION=true \
TETHERPANE_UI_REDUCE_TRANSPARENCY=true \
./script/build_and_run.sh --verify
```

Presentation overrides are ignored unless `TETHERPANE_UI_FIXTURE` names a recognized fixture. Omit the variables to launch against live discovery and the real system appearance and accessibility preferences.

## Optional follow-up cleanup

The project is Xcode-native for app development and archives. Two non-blocking cleanup opportunities remain if the maintainers later choose to make SwiftPM compatibility optional:

1. Add an XCTest target and migrate the executable seam contracts once the full Xcode toolchain is the required baseline on every maintainer machine. The current seam runner already executes in the verified repository test workflow. Future tests should continue crossing only the domain and adapter interfaces described in `CONTEXT.md`, plus the isolated visual-QA resolver in `TetherPaneUIFixtureSupport`.
2. Rename the internal pre-public module and source-directory names (`AirDroidDomain`, `AirDroidScrcpy`, and `AirDroidMac`) in one mechanical, separately reviewed change. They are not user-visible and remain unchanged now to keep the release migration small and auditable.

Do not move source files into duplicate Xcode-only directories. A source file must be owned by one module even when both Xcode and SwiftPM can build it.
