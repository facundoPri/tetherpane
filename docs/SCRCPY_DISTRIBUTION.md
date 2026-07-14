# Distributing stock scrcpy 4.1

## Current beta decision

TetherPane currently treats stock scrcpy 4.1 and ADB as external host tools. This is the lowest-risk public beta path:

```bash
brew install scrcpy
brew install --cask android-platform-tools
```

Contributors can install both through `brew bundle --file Brewfile`. TetherPane resolves explicit `SCRCPY_PATH` and `ADB_PATH` overrides first, then standard Homebrew locations, then `PATH`.

## Can the app bundle them?

Yes. The official scrcpy 4.1 GitHub release publishes separate macOS ARM64 and x86_64 archives. Each archive is about 13 MB and contains the stock `scrcpy` client, `scrcpy-server`, a universal `adb`, artwork, manual page, and Apache-2.0 license. A 2026-07-14 inspection verified the published checksums:

| Archive | SHA-256 |
| --- | --- |
| `scrcpy-macos-aarch64-v4.1.tar.gz` | `20fd47c9014dd5e0fa77091f3cb7adbda8445a360c4584aeaa0150b5b3988ff3` |
| `scrcpy-macos-x86_64-v4.1.tar.gz` | `ee2a7223bc8dbdc4f482db1134bcf441178dafb833492b71ca4c22090c58ce72` |

The client is effectively self-contained and links only Apple system frameworks. The included ADB binary is universal. That makes bundling technically straightforward, but it is still release engineering rather than a Swift Package dependency.

## Recommended stable-release design

1. Download the two unmodified upstream archives during a controlled release build, never at application runtime.
2. Verify the pinned SHA-256 values before extracting anything.
3. Put the architecture-specific stock client plus its server and assets under `Contents/Library/scrcpy/<architecture>/`; keep the universal ADB once.
4. Include upstream `LICENSE` and a third-party notice in the application resources and release archive.
5. Make `DeveloperToolPathResolver` prefer the bundled tools, while retaining explicit environment overrides for diagnostics.
6. Sign the nested `scrcpy` and `adb` executables with the same Developer ID identity before signing the outer app, then notarize and staple the complete bundle.
7. Verify both architectures, USB, secure Wireless Debugging, USB-assisted Wi-Fi, recording, audio, process cleanup, and exact-device `-s` targeting on quarantined release artifacts.

This preserves stock scrcpy 4.1 behavior and removes the Homebrew requirement. The implementation is moderate—roughly a focused release slice—because the download and runtime selection are simple, while nested signing, notices, two-architecture acceptance, update policy, and notarization need careful verification.

Do not silently run Homebrew from the GUI. An in-app installer would need explicit consent, visible progress, cancellation, error recovery, and a clear explanation of network and disk changes. Bundling the pinned upstream release is a cleaner stable-user experience.

Sources: [official scrcpy 4.1 release](https://github.com/Genymobile/scrcpy/releases/tag/v4.1), [official macOS instructions](https://github.com/Genymobile/scrcpy/blob/v4.1/doc/macos.md), [scrcpy license](https://github.com/Genymobile/scrcpy/blob/v4.1/LICENSE), and [Homebrew formula](https://formulae.brew.sh/formula/scrcpy.html).
